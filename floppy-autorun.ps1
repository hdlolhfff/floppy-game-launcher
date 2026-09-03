[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z]:\\$')]
    [string]$Drive = 'A:\',

    [ValidateNotNullOrEmpty()]
    [string]$FileName = 'autorun.txt'
)

$ErrorActionPreference = 'SilentlyContinue'

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class FloppyWindowCloser
{
    private delegate bool EnumWindowsCallback(IntPtr window, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    public static int CloseWindowsForProcess(int processId)
    {
        var count = 0;
        EnumWindows(delegate(IntPtr window, IntPtr parameter)
        {
            uint windowProcessId;
            GetWindowThreadProcessId(window, out windowProcessId);
            if (windowProcessId == processId && PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero))
            {
                count++;
            }
            return true;
        }, IntPtr.Zero);
        return count;
    }
}
'@

$logPath = Join-Path $PSScriptRoot 'floppy-autorun.log'
$diskSessionActive = $false
$notReadySince = $null
$activeConfig = $null
$launchedProcessId = $null

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)

    Add-Content -LiteralPath $logPath -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message) -Encoding UTF8
}

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

    if (-not $gameProcesses) {
        Write-Log 'No running game process was found to close.'
    }

    $gameProcesses | ForEach-Object {
        # WM_CLOSE lets the game perform its normal save-and-exit handling.
        $closeRequested = $_.CloseMainWindow()
        $fallbackWindowCount = 0
        if (-not $closeRequested) {
            $fallbackWindowCount = [FloppyWindowCloser]::CloseWindowsForProcess($_.Id)
        }
        Write-Log "Close request sent to $($_.ProcessName) (PID $($_.Id)); accepted=$closeRequested, fallbackWindows=$fallbackWindowCount."
    }
}

$driveName = $Drive.TrimEnd('\')
$eventSource = "FloppyGameLauncher-$PID"
$eventQuery = "SELECT * FROM Win32_VolumeChangeEvent WHERE DriveName = '$driveName'"
Register-WmiEvent -Query $eventQuery -SourceIdentifier $eventSource
$eventRegistration = Get-EventSubscriber -SourceIdentifier $eventSource
Write-Log "Watcher started for $Drive$FileName; volume events enabled=$([bool]$eventRegistration)."

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
        Write-Log "Windows volume event received; type=$eventType, drive=$driveName."
        if ($eventType -in 2, 3 -and $diskSessionActive) {
            Write-Log 'Resetting the active disk session after a volume arrival or removal event.'
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
        Write-Log "Detected $autorunPath."
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
            try {
                if ($config['arguments']) {
                    $launchedProcess = Start-Process -FilePath $executable -ArgumentList $config['arguments'] -PassThru -ErrorAction Stop
                }
                else {
                    $launchedProcess = Start-Process -FilePath $executable -PassThru -ErrorAction Stop
                }
                $launchedProcessId = $launchedProcess.Id
                Write-Log "Launched $executable (PID $launchedProcessId)."
            }
            catch {
                Write-Log "Launch failed for $executable`: $($_.Exception.Message)"
            }
        }
        else {
            Write-Log "Configured executable was not found: $executable"
        }

        $diskSessionActive = $true
    }

    if ($diskSessionActive -and $isReady) {
        if ($null -ne $notReadySince) {
            Write-Log 'The media became available again before ejection was confirmed.'
        }
        $notReadySince = $null
    }
    elseif ($diskSessionActive -and $null -eq $notReadySince) {
        $notReadySince = [DateTime]::UtcNow
        Write-Log "$autorunPath is unavailable; waiting for the next check to confirm ejection."
    }
    elseif ($diskSessionActive -and ([DateTime]::UtcNow - $notReadySince).TotalSeconds -ge 3) {
        Write-Log 'Disk ejection confirmed.'
        Close-ActiveGame -Config $activeConfig -ProcessId $launchedProcessId
        $activeConfig = $null
        $launchedProcessId = $null
        $diskSessionActive = $false
        $notReadySince = $null
    }
}
