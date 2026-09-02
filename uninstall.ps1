[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$installDirectory = Join-Path $env:LOCALAPPDATA 'FloppyGameLauncher'
$installedScript = Join-Path $installDirectory 'floppy-autorun.ps1'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Floppy Game Launcher.lnk'

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$installedScript*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $installDirectory -Recurse -Force -ErrorAction SilentlyContinue

Write-Host 'Floppy Game Launcher has been uninstalled.'
