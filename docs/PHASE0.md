# Phase 0: does CS2 run on Recall's engine?

Before porting the app, we answer one question by hand: can Recall's existing Wine + DXMT
engine run Windows Steam and Counter-Strike 2 well enough to be worth it? Everything here
runs from `scripts/cs2_spike.sh` in its own folder (`~/RecallCS2-spike`, or `SPIKE_ROOT`),
separate from any Recall or Overwatch install.

> **Use an alt Steam account, and keep VAC off.** The spike always starts CS2 with
> `-insecure`, which disables VAC (Valve's anti-cheat) and keeps you out of official
> matchmaking. Play offline with bots, on a community server, or in the Workshop
> benchmark map. Don't remove `-insecure` until we've worked through the VAC question.

## What you need

- An Apple Silicon Mac on macOS 26.5 or later, with Rosetta
  (`softwareupdate --install-rosetta --agree-to-license`)
- About 70 GB free (CS2 is ~60 GB)
- A Steam account that owns CS2 (it's free)
- Recall 1.3.0 from [its releases page](https://github.com/AsherJN/recall/releases/latest).
  We only borrow its engine. You don't need to open or set it up.

## Steps

**1. Get the engine.** Install `Recall.app` (or mount its DMG), then:

```sh
scripts/cs2_spike.sh engine /Applications/Recall.app
```

This copies the bundled `runtime.tar.gz` into `~/RecallCS2-spike/engine`.

**2. Create the Wine environment.**

```sh
scripts/cs2_spike.sh init
```

**3. Install Steam.**

```sh
scripts/cs2_spike.sh install-steam
```

**4. Open Steam, sign in, and install CS2.**

```sh
scripts/cs2_spike.sh steam-cx      # needs CrossOver in /Applications
```

This opens Steam with CrossOver's own Wine. Recall's Wine can run Steam, but its window
stays black (see "What we've found" below). Steam updates itself the first time it opens
(about 340 MB, no window while it does), so wait a minute or two. Sign in, install
Counter-Strike 2 from the Library, then quit Steam (Steam menu → Exit, or
`scripts/cs2_spike.sh steam-cx stop`) before starting the game on Recall's engine.

**5. Start CS2.**

```sh
scripts/cs2_spike.sh cs2                     # through Steam, at 1920 × 1200
CS2_WIDTH=1920 CS2_HEIGHT=1080 scripts/cs2_spike.sh cs2   # 16:9 external monitor
SPIKE_HUD=1 scripts/cs2_spike.sh cs2         # with Apple's Metal HUD showing FPS
```

This starts Steam hidden (`-silent`) on Recall's engine, and Steam starts CS2. If nothing
happens after a minute, try `scripts/cs2_spike.sh cs2-direct` while that Steam is still
running.
Load a map with bots (Play → Practice), or the Workshop benchmark map
(search "CS2 FPS Benchmark").

**6. Stop everything** when you're done, or before retrying:

```sh
scripts/cs2_spike.sh stop
```

## When something fails

Rerun the failing step with logs on, then send me the matching file from
`~/RecallCS2-spike/logs/` (`steam.log`, `cs2.log`, or DXMT's own log):

```sh
SPIKE_DEBUG=1 scripts/cs2_spike.sh cs2
```

Debug logging slows the game down, so turn it off for performance checks.

## What to report back

| Check | Result |
|---|---|
| Steam window opens and you can sign in (which `STEAM_FLAGS`?) | |
| CS2 downloads and installs | |
| CS2 reaches the main menu | |
| A map loads and renders correctly (no missing or garbled geometry, smoke, or UI) | |
| Average FPS and settings (Metal HUD, or `cl_showfps 1` in the console) | |
| Mouse feels right in game (also try `SPIKE_MOUSELOOK=0` to compare) | |
| Fullscreen, Alt-Tab / Cmd-Tab back to the game | |
| Sound, and voice chat if you can test it | |
| Stutters while loading new areas or the first time effects appear | |
| Crashes (when, and the last lines of `cs2.log`) | |

What happens next depends on the results:

- **Menu and maps render, playable FPS.** Go ahead with Phase 1 (identity) and Phase 2 (Steam in the worker).
- **Steam fails but CS2 is fine with `cs2-direct`.** Phase 2 needs Steam-specific fixes first.
- **CS2 crashes or renders wrong on DXMT.** Look at DXMT's logs before anything else. The
  fallback is CS2's Vulkan mode (`-vulkan`) on MoltenVK, which this engine doesn't include yet.

## What we've found

- **`-noverifyfiles` stops Steam's first install.** Steam skips downloading its client and
  sits idle with no window. The script no longer passes it.
- **Steam's browser crashes on Wine's Core Audio when run from Terminal.** An assertion in
  `mmdevapi` (`mmdevapi_private.h:120`) shuts the browser down before any window appears.
  `init` turns Wine's sound off; `scripts/cs2_spike.sh audio on` turns it back on. Sound for
  CS2 itself is still to be tested.
- **Recall's Mac driver patches break Steam's window.** With software drawing the window is
  a black box; with GPU drawing (through DXMT) it never appears (`EGL_BAD_ALLOC` creating a
  swap chain). The same Steam install draws normally on CrossOver 25.0.1's unpatched Wine.
  Phase 2 has to keep the fullscreen game handling to the game's own windows, or fix the
  patches for ordinary windows.
