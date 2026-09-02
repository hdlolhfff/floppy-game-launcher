[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$sourcePath = Join-Path $PSScriptRoot 'floppy-autorun.ps1'
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Watcher script was not found at $sourcePath."
}

$installDirectory = Join-Path $env:LOCALAPPDATA 'FloppyGameLauncher'
$installedScript = Join-Path $installDirectory 'floppy-autorun.ps1'
$startupDirectory = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupDirectory 'Floppy Game Launcher.lnk'

New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
Copy-Item -LiteralPath $sourcePath -Destination $installedScript -Force

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $PSHOME 'powershell.exe'
$shortcut.Arguments = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installedScript`""
$shortcut.WorkingDirectory = $installDirectory
$shortcut.WindowStyle = 7
$shortcut.Description = 'Launch games configured by A:\autorun.txt'
$shortcut.Save()

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$installedScript*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Start-Process `
    -FilePath (Join-Path $PSHOME 'powershell.exe') `
    -ArgumentList '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$installedScript`"" `
    -WindowStyle Hidden

Write-Host 'Floppy Game Launcher is installed and running.'
