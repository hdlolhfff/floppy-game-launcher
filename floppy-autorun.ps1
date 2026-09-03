[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z]:\\$')]
    [string]$Drive = 'A:\',

    [ValidateNotNullOrEmpty()]
    [string]$FileName = 'autorun.txt'
)

$ErrorActionPreference = 'SilentlyContinue'
$diskSessionActive = $false
$notReadySince = $null
$activeConfig = $null
$launchedProcessId = $null

function Close-ActiveGame {
    param(
        [hashtable]$Config,
        $ProcessId
    )

    $gameProcesses = @()
    if ($Config['process']) {
        $processName = [IO.Path]::GetFileNameWithoutExtension($Config['process'])
        $gameProcesses = Get-Process -Name $processName
    }
    elseif ($ProcessId) {
        $gameProcesses = Get-Process -Id $ProcessId
    }

    $gameProcesses | ForEach-Object {
        # WM_CLOSE lets the game perform its normal save-and-exit handling.
        $_.CloseMainWindow() | Out-Null
    }
}

$driveName = $Drive.TrimEnd('\')
$eventSource = "FloppyGameLauncher-$PID"
$eventQuery = "SELECT * FROM Win32_VolumeChangeEvent WHERE DriveName = '$driveName'"
$eventRegistration = Register-WmiEvent -Query $eventQuery -SourceIdentifier $eventSource

while ($true) {
    if ($eventRegistration) {
        $volumeEvent = Wait-Event -SourceIdentifier $eventSource -Timeout 4
    }
    else {
        Start-Sleep -Seconds 4
        $volumeEvent = $null
    }

    if ($volumeEvent) {
        $eventType = $volumeEvent.SourceEventArgs.NewEvent.EventType
        Remove-Event -EventIdentifier $volumeEvent.EventIdentifier
        if ($eventType -in 2, 3 -and $diskSessionActive) {
            Close-ActiveGame -Config $activeConfig -ProcessId $launchedProcessId
            $activeConfig = $null
            $launchedProcessId = $null
            $diskSessionActive = $false
            $notReadySince = $null
        }
    }

    $autorunPath = Join-Path $Drive $FileName
    $isReady = [IO.File]::Exists($autorunPath)

    if ($isReady -and -not $diskSessionActive) {
        $config = @{}
        foreach ($line in [IO.File]::ReadAllLines($autorunPath)) {
            if ($line -match '^\s*([^#;][^=]*)=(.*)$') {
                $key = $Matches[1].Trim().ToLowerInvariant()
                $value = $Matches[2].Trim()
                if ($value.Length -ge 2 -and $value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') {
                    $value = $value.Substring(1, $value.Length - 2)
                }
                $config[$key] = $value
            }
        }

        $activeConfig = $config
        $launchedProcessId = $null

        $executable = [Environment]::ExpandEnvironmentVariables($config['path'])
        if ($executable -and [IO.File]::Exists($executable)) {
            if ($config['arguments']) {
                $launchedProcess = Start-Process -FilePath $executable -ArgumentList $config['arguments'] -PassThru
            }
            else {
                $launchedProcess = Start-Process -FilePath $executable -PassThru
            }
            $launchedProcessId = $launchedProcess.Id
        }

        $diskSessionActive = $true
    }

    if ($diskSessionActive -and $isReady) {
        $notReadySince = $null
    }
    elseif ($diskSessionActive -and $null -eq $notReadySince) {
        $notReadySince = [DateTime]::UtcNow
    }
    elseif ($diskSessionActive -and ([DateTime]::UtcNow - $notReadySince).TotalSeconds -ge 3) {
        Close-ActiveGame -Config $activeConfig -ProcessId $launchedProcessId
        $activeConfig = $null
        $launchedProcessId = $null
        $diskSessionActive = $false
        $notReadySince = $null
    }
}
