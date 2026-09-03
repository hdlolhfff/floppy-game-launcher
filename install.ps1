[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $elevated = Start-Process `
        -FilePath (Join-Path $PSHOME 'powershell.exe') `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"" `
        -Verb RunAs `
        -Wait `
        -PassThru
    exit $elevated.ExitCode
}

$sourcePath = Join-Path $PSScriptRoot 'floppy-autorun.ps1'
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Watcher script was not found at $sourcePath."
}

$installDirectory = Join-Path $env:LOCALAPPDATA 'FloppyGameLauncher'
$installedScript = Join-Path $installDirectory 'floppy-autorun.ps1'
$startupDirectory = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupDirectory 'Floppy Game Launcher.lnk'
$taskName = 'Floppy Game Launcher'

New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
Copy-Item -LiteralPath $sourcePath -Destination $installedScript -Force

Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$installedScript*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue

$taskAction = New-ScheduledTaskAction `
    -Execute (Join-Path $PSHOME 'powershell.exe') `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installedScript`""
$taskTrigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Highest
$taskSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $taskAction `
    -Trigger $taskTrigger `
    -Principal $taskPrincipal `
    -Settings $taskSettings `
    -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

Write-Host 'Floppy Game Launcher is installed and running.'
