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

$installDirectory = Join-Path $env:LOCALAPPDATA 'FloppyGameLauncher'
$installedScript = Join-Path $installDirectory 'floppy-autorun.ps1'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Floppy Game Launcher.lnk'
$taskName = 'Floppy Game Launcher'

Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$installedScript*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $installDirectory -Recurse -Force -ErrorAction SilentlyContinue

Write-Host 'Floppy Game Launcher has been uninstalled.'
