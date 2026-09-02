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

while ($true) {
    $autorunPath = Join-Path $Drive $FileName
    $isReady = [IO.Directory]::Exists($Drive)

    if ($isReady -and -not $diskSessionActive -and [IO.File]::Exists($autorunPath)) {
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
        $gameProcesses = @()
        if ($activeConfig['process']) {
            $processName = [IO.Path]::GetFileNameWithoutExtension($activeConfig['process'])
            $gameProcesses = Get-Process -Name $processName
        }
        elseif ($launchedProcessId) {
            $gameProcesses = Get-Process -Id $launchedProcessId
        }

        $gameProcesses | ForEach-Object {
            # WM_CLOSE lets the game perform its normal save-and-exit handling.
            $_.CloseMainWindow() | Out-Null
        }
        $activeConfig = $null
        $launchedProcessId = $null
        $diskSessionActive = $false
        $notReadySince = $null
    }

    Start-Sleep -Seconds 2
}
