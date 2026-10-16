---
title: "macsl-crossover"
subtitle: "SCP: Secret Laboratory on DXMT, in CrossOver and NotProton"
date: "16 October 2026"
---

# What it does

`macsl-crossover` makes SCP: Secret Laboratory use **DXMT**, the Direct3D 11 to Metal backend
that ships with CrossOver. It covers every place the game runs on this Mac:

- your **CrossOver bottles** that have the game installed (`Steamm` with Rosetta, `arm64` with FEX),
- **macOS Steam with NotProton**, on both its Rosetta and its FEX compatibility tools.

It keeps the setting in place by itself, including after CrossOver updates. It doesn't install
anything game-related and it changes nothing inside CrossOver.app or NotProton.

# Quick start

```
macsl-crossover dxmt        # use DXMT everywhere (already done on this Mac)
macsl-crossover auto on     # keep it that way (already on)
macsl-crossover status      # check
```

Then start the game the way you normally do: from CrossOver, or from macOS Steam.

| Command | What it does |
|---|---|
| `status` | Shows the chosen backend, each bottle's backend, Steam's launch options, and whether auto is on |
| `dxmt` | Chooses DXMT and applies it everywhere; offers to restart CrossOver's Steam |
| `d3dmetal` | Chooses D3DMetal (CrossOver's default) for Rosetta; ARM64/FEX stays on DXMT |
| `ensure` | Re-applies the chosen backend wherever something reset it. Auto runs this for you |
| `auto on` / `auto off` | Starts / stops the background agent that keeps the choice applied |
| `play [bottle]` | Launches SCP:SL in a CrossOver bottle (the first one with the game by default) |
| `undo` | Auto off, then restores every file from the backups this tool made |

The command lives in your fork, `~/Documents/MacVolvo/crossover/macsl-crossover.sh`, and is
linked as `~/.local/bin/macsl-crossover`.

# How it works

## The one setting that matters

CrossOver picks its graphics backend from a single environment variable,
`CX_GRAPHICS_BACKEND` (`d3dmetal`, `dxmt`, `dxvk` or `wined3d`). CrossOver's Wine reads it when a
Windows program starts and loads the matching DLLs (for DXMT: `d3d11.dll`, `dxgi.dll` and
`winemetal.dll` from `CrossOver/lib/dxmt`). `macsl-crossover` only ever sets this variable, in two
places.

## CrossOver bottles

Each bottle has a `cxbottle.conf` with an `[EnvironmentVariables]` section that CrossOver applies
to everything started in that bottle. The tool sets

```
"CX_GRAPHICS_BACKEND" = "dxmt"
```

in every bottle where `SCPSL.exe` is installed. Programs that are already running keep the old
backend: Steam passes its own environment to the game, so CrossOver's Steam has to restart once
(`dxmt` offers to do it). After that, every launch from CrossOver uses DXMT.

## macOS Steam with NotProton

NotProton runs Windows games from macOS Steam through a copy of CrossOver's engine. Its
compatibility tool passes any `CX_GRAPHICS_*` / `DXMT_*` variables from the game's Steam launch
options into Wine. The tool sets SCP:SL's launch options (Steam > SCP:SL > Properties) to

```
CX_GRAPHICS_BACKEND=dxmt NOTPROTON_RETINA=0 WINEMSYNC=1 %command%
```

replacing only the `CX_GRAPHICS_BACKEND=…` part and keeping the rest of your options.

macOS Steam keeps its own copy of launch options while it runs and rewrites the file
(`userdata/<account>/config/localconfig.vdf`) when it quits. So the change is only made while
macOS Steam is closed. With auto on, it's applied the moment Steam quits.

## Keeping it applied (auto)

`auto on` installs a LaunchAgent, `~/Library/LaunchAgents/app.macsl.ensure.plist`, that runs
`macsl-crossover ensure`:

- at login, and every 30 minutes,
- when any bottle's `cxbottle.conf` changes, or a bottle is added or removed,
- when Steam's `localconfig.vdf` changes (for example when Steam quits),
- when CrossOver.app or CrossOver Preview.app changes (an update),
- when NotProton adds a compatibility tool (`Steam/compatibilitytools.d`).

`ensure` does nothing when everything is already set, so it's safe to run any number of times.
launchd can't read `~/Documents` (macOS privacy protection), so the agent runs a copy of the
script from `~/.local/share/macsl/`. `auto on` refreshes that copy. Its log is
`~/Library/Logs/macsl-ensure.log`.

Your choice is stored in `~/.config/macsl/backend`. If you switch to `d3dmetal`, auto keeps
D3DMetal instead.

# Rosetta, ARM64/FEX and new CrossOver versions

## Rosetta and FEX

| Where the game runs | DXMT | Checked |
|---|---|---|
| CrossOver bottle `Steamm` (x86-64 Wine, Rosetta) | Yes | Verified 16 Oct: `Renderer: Apple M4 Max` in Player.log |
| CrossOver bottle `arm64` (ARM64 Wine, FEX) | Yes | Bottle already set to DXMT; the game ran there on DXMT (Player.log, 3 Aug, older CrossOver build) |
| NotProton, Rosetta tool | Yes | Verified 16 Oct on build 41073: `Renderer: Apple M4 Max` |
| NotProton, FEX tool | Expected | DXMT's ARM64 files are in the runner, and NotProton passes `dxmt` through under FEX. Not launched yet |

D3DMetal only exists for x86-64 (Rosetta). That's why `d3dmetal` leaves ARM64 bottles on DXMT,
and why NotProton removes `CX_GRAPHICS_BACKEND=d3dmetal` itself when you pick its FEX tool.
DXMT ships both x86-64 and ARM64 builds (`lib/dxmt/x86_64-*` and `aarch64-*`), so DXMT works on
both.

## New CrossOver versions

Nothing this tool changes lives inside CrossOver, so an update can't overwrite it:

- **CrossOver bottles** keep their `cxbottle.conf` across updates. If an update or a bottle
  upgrade ever resets the backend, the agent sees the file change and sets it back.
- **NotProton** builds a new compatibility tool for each CrossOver build (it made
  `notproton-fex-rosetta-41073` after this morning's update) and moves the game to it. Launch
  options belong to the game, not the tool, so `CX_GRAPHICS_BACKEND=dxmt` carries over.
- **CrossOver moving or being renamed** (this morning's update dropped a trailing space from the
  app's name) is handled: the tool looks for CrossOver in `/Applications` and `~/Applications`
  each time it runs.

There's nothing to do after an update. Run `macsl-crossover status` if you want to see it.

# Checking it worked

The game writes the renderer it got into its log. `Apple M4 Max` means DXMT;
`AMD Compatibility Mode` means D3DMetal.

| Launched from | Player.log |
|---|---|
| CrossOver, bottle `Steamm` | `~/Library/Application Support/CrossOver/Bottles/Steamm/drive_c/users/crossover/AppData/LocalLow/Northwood/SCPSL/Player.log` |
| CrossOver, bottle `arm64` | same path with `arm64` in place of `Steamm` |
| macOS Steam (NotProton) | `~/Library/Application Support/Steam/steamapps/compatdata/700330/pfx/drive_c/users/steamuser/AppData/LocalLow/Northwood/SCPSL/Player.log` |

```
grep Renderer: "<Player.log path>"
```

# Getting the most out of it

- **Compare DXMT and D3DMetal in a round, not the menu.** SCP:SL caps the menu and loading
  screens at 60 fps. Join a populated server, play a few minutes on each backend and compare.
  Switch with `macsl-crossover d3dmetal` / `dxmt` and restart Steam in between.
- **For an on-screen fps counter while testing**, add `MTL_HUD_ENABLED=1` to SCP:SL's Steam
  launch options (NotProton) and remove it afterwards. The global Metal HUD is off.
- **Never start Wine commands from Desktop, Documents or Downloads.** The wineserver opens the
  current folder, macOS asks for permission, and every Wine program, including the game, freezes
  until someone answers. The tool always runs from your home folder.
- **Known issue: a short hitch about every 5 seconds.** Measured under D3DMetal last night; it
  looks like a thread-suspend pause in the game process under Wine. A candidate fix
  (`job-worker-count` in the game's `boot.config`) is untested.

# Troubleshooting

| Symptom | Fix |
|---|---|
| `status` shows `d3dmetal` somewhere | `macsl-crossover ensure` (or wait: auto fixes it within 30 min) |
| "macOS Steam is running; will apply after it quits" | Quit macOS Steam; auto applies it straight away |
| Game still reports `AMD Compatibility Mode` | Steam was already running: restart CrossOver's Steam, or quit and reopen macOS Steam |
| Black screen or crash on DXMT | `macsl-crossover d3dmetal`, restart Steam, and report it |
| Auto doesn't seem to run | `macsl-crossover auto on` again; check `~/Library/Logs/macsl-ensure.log` |
| Want everything back as it was | `macsl-crossover undo` (quit macOS Steam first for its launch options) |

# Files it touches

| File | Change | Backup |
|---|---|---|
| `…/CrossOver/Bottles/<bottle>/cxbottle.conf` | `CX_GRAPHICS_BACKEND` line | `cxbottle.conf.macsl-backup` (first change only) |
| `…/Steam/userdata/<account>/config/localconfig.vdf` | SCP:SL's `LaunchOptions` | `localconfig.vdf.macsl-backup` |
| `~/.config/macsl/backend` | your chosen backend | n/a |
| `~/Library/LaunchAgents/app.macsl.ensure.plist` | the auto agent | removed by `auto off` |
| `~/.local/share/macsl/` | copy of the scripts the agent runs | n/a |

Not touched: CrossOver.app, NotProton's files and tools, the game's files, your Windows Steam
settings.

# Limits

- **This is CrossOver's stock DXMT.** Recall's speed-ups (frame pacing, the fixed-size fullscreen
  canvas, 2,000 Hz raw mouse) need Recall's own patched Wine. They're only in the standalone MacSL
  app, not in CrossOver or NotProton.
- **Whether DXMT is faster than D3DMetal for SCP:SL hasn't been measured yet.** Compare both in a
  round.
- **Anti-cheat:** SCP:SL ships Northwood's own anti-cheat (`SL-AC.dll`). The game runs unmodified,
  as it always has under CrossOver, but Northwood doesn't support playing this way.
