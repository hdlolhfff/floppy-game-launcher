# Floppy Game Launcher

Turn floppy disks into physical game launchers on Windows. Inserting a disk containing `autorun.txt` launches its configured game. Ejecting the disk requests a graceful close so the game can perform its normal save-and-exit handling.

## Features

- Watches floppy drive `A:\` in the background.
- Launches one game per disk insertion.
- Supports direct executables and launchers such as Hydra or Steam.
- Closes the configured game when the disk has been absent for three seconds.
- Debounces temporary floppy read failures to prevent duplicate launches.
- Starts automatically when the current user signs in.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1
- A floppy drive assigned to `A:\`

## Install

Download or clone this repository, open PowerShell in its folder, and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

The installer copies the watcher to `%LOCALAPPDATA%\FloppyGameLauncher`, creates a shortcut in the current user's Startup folder, and starts it immediately. Administrator access is not required.

## Configure A Disk

Create `autorun.txt` in the root of the floppy. A directly launched game only needs `path`; `title` and `arguments` are optional:

```ini
title=Example Game
path="C:\Games\Example Game\ExampleGame.exe"
arguments="-fullscreen"
```

Environment variables in `path` are supported:

```ini
path="%LOCALAPPDATA%\Programs\Example\Example.exe"
```

### Games Started By A Launcher

When Hydra, Steam, or another launcher starts the game, add `process` with the game's executable name. This tells the watcher which process to close when the disk is ejected.

Hydra example:

```ini
title=Geometry Dash
path="%LOCALAPPDATA%\Programs\Hydra\Hydra.exe"
arguments="hydralauncher://run?shop=steam&objectId=322170"
process=GeometryDash
```

Do not include `.exe` in `process`. You can find the process name in Task Manager under the **Details** tab while the game is running.

## How It Works

The watcher checks `A:\` once every four seconds. It parses `autorun.txt` and launches the configured executable once for that disk session. A disk must remain unavailable for three seconds before the watcher treats it as ejected; this avoids duplicate launches caused by temporary read failures.

On ejection, the watcher sends the game a standard Windows close request (`WM_CLOSE`). It does not force-kill the process.

## Saving Limitation

A graceful close gives the game an opportunity to run its normal save-on-exit behavior, but the watcher cannot guarantee that every game saves. Games that only save through an in-game menu must still be saved manually before ejecting the disk.

## Security

Only use trusted floppy disks. Anyone who can modify `autorun.txt` can configure the watcher to launch an executable already present on your computer.

## Uninstall

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```
