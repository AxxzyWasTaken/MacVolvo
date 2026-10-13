# Handoff: where Phase 0 stands (2026-10-13)

Written for an agent or developer picking this up mid-task. Read `README.md`,
`docs/PHASE0.md` and `scripts/cs2_spike.sh` first. Nothing below is committed; the
owner's rule is **no git commit/push and no build commands without their explicit
instruction** (they approved the winemac build described in "Current task").

## Goal

Fork Recall (Overwatch on Mac: Wine + Rosetta + DXMT, see `docs/HOW-IT-WORKS.md`) into an
app for Valve's Source 2 games on Steam: Counter-Strike 2 first, Deadlock as a second
profile. Phase 0 = prove the engine runs them by hand, before porting the app.

## Spike setup (on the owner's Mac)

- Everything lives in `~/RecallCS2-spike` (override with `SPIKE_ROOT`).
- `engine/` = Recall 1.3.0's runtime, extracted by `scripts/cs2_spike.sh engine`.
- `env-cx/` = **the Wine environment in use** (Steam signed in, Deadlock installed). Every
  command needs `SPIKE_ENV=env-cx`. `environment/` is an older copy with Steam only;
  ignore it.
- `logs/` = per-command logs (`steam.log`, `deadlock.log`, `steam-trace.log`, ...).
- Steam with a working window: `SPIKE_ENV=env-cx scripts/cs2_spike.sh steam-cx` (uses
  `/Applications/CrossOver.app` 25.0.1's Wine). Stop it with `steam-cx stop`.
- Game on Recall's engine: `SPIKE_ENV=env-cx SPIKE_HUD=1 scripts/cs2_spike.sh deadlock`
  (or `cs2`). Stop with `scripts/cs2_spike.sh stop` (with `SPIKE_ENV=env-cx`).
- Only one Wine may use `env-cx` at a time: always `stop` before switching engines.

## Results so far

| | Result |
|---|---|
| Deadlock on Recall's engine (DXMT) | Boots, renders, plays. Aim good with Recall's raw mouse input (`WINEMAC_MOUSELOOK` lists `deadlock.exe`). |
| Game Mode | Works: `make_game_apps` in the script clones the engine's `game-mode/Overwatch.app` into `deadlock.app` / `cs2.app` (ad-hoc signed, same entitlements) and sets `WINE_GAME_MODE`. |
| Audio | Works for the game; slight buzz, mostly gone after setting the Mac speakers to 48 kHz. |
| Lag spikes in fights | Probably first-time shader compilation (≈190 MB of caches built in one session). Unconfirmed: needs a second session in the same areas. |
| CS2 | Not tested yet (needs installing via `steam-cx`). Same engine as Deadlock. |
| Steam's own window on Recall's engine | **Black.** Current task. |

Facts learned (all in `docs/PHASE0.md` too):
- Deadlock's executable is `deadlock.exe` (not `project8.exe`), app ID 1422450.
- `-noverifyfiles` stops Steam's first-run download. Removed.
- Run from Terminal, Steam's browser hits a Wine Core Audio assertion
  (`mmdevapi_private.h:120`) when audio is on. `scripts/cs2_spike.sh audio off|on`.
  With the game started from its Game Mode bundle, audio on worked.
- Launch flags in use: `-insecure` (VAC off; alt account only), `-nojoy`, `-dx11`.

## Current task: Steam's window is black on Recall's engine

What is ruled out:
- Not the launch environment: bare `env -i` Wine on Recall's engine is still black.
- Not DXMT: giving `steam.exe`/`steamwebhelper.exe` Wine's own `wined3d` (CrossOver's
  `d3d11/dxgi/d3d10core/wined3d` copied into Steam's folder with the "Wine builtin DLL"
  header marker renamed, plus `AppDefaults` `native,builtin`) loaded fine and was still
  black. Those test files and registry keys have been removed.
- Not SDL's renderer choice (`SDL_RENDER_DRIVER=software` black, `direct3d11` crashes Steam).
- Not DXMT's fullscreen canvas: it only activates with `dxgi.nativeFullscreen`.
- Plain GDI windows (notepad, winecfg) draw fine on Recall's engine.
- Same Steam install draws normally on CrossOver's Wine (25.0.1 here; owner says CrossOver
  worked for them before too).

What is known about Steam's drawing: its visible windows are `SDL_app` windows owned by
`steam.exe` (SDL3). The browser renders off screen; `steam.exe` composes the frames into its
window. A `+wgl` trace showed one `wglSwapBuffers` per session on both engines, so the frames
are not presented through OpenGL swaps.

**Update (03:30): bisect results.** With Screen Recording now granted, a CGWindowList dump
(Swift script, `CGWindowListCopyWindowInfo`) showed the black window is owned by the
**steamwebhelper browser process** (title "Steam", 1144x815; Steam's "System" composer mode
draws straight into the browser's HWND), not by `steam.exe`. Steam is signed in behind it.
Ruled out, each tested on its own on Recall's engine, all still black:
- stock CrossOver 26.3 `winemac.so` (built from source, see below), i.e. none of the three
  Mac driver patches;
- stock 26.3 `win32u.so` (so not `wine-win32u-display-log.patch`);
- every webhelper process (browser, gpu-process, renderers) on Wine's own `wined3d`
  (`dxgi`/`d3d11`/`wined3d` copies in `bin/cef/cef.win64`, verified with `lsof`), so not DXMT.
The engine is restored to the shipped files (`*.recall` backups next to them in
`engine/lib/wine/x86_64-unix/`); test DLLs and AppDefaults keys removed.

Build setup that works (all under `runtime/`, git-ignored): source extracted to
`runtime/source/cx26/sources/wine` (archive SHA-256 matches the pinned
`ac99c8ca…6872`); toolchain `runtime/toolchains/llvm-mingw-20261006-ucrt-macos-universal`
(needed: Wine's configure wants a PE cross-compiler even for Unix-side builds; Homebrew `lld`
refused to install on these Command Line Tools); configured out of tree in
`runtime/build/cx26-x64` (see `configure.log` for the command: `arch -x86_64`,
`--enable-archs=x86_64 --without-x --disable-tests` plus many `--without-*`), with
`SONAME_LIBVULKAN`/`SONAME_LIBMOLTENVK` defined by hand in `include/config.h` as
`@rpath/libMoltenVK.dylib`. `make dlls/winemac.drv/winemac.so` builds in a minute. To drop a
built `.so` into the engine: `install_name_tool -add_rpath @loader_path/../..`, then
`codesign --force -s -`.

Remaining suspects: `ntdll.so` (`wine-ntdll-syscall-log`, `wine-portable-directory-boolean`),
`wineserver` (`wine-server-registry-save`), Recall/Soju's build configuration, or upstream
Wine 26.3 itself (the working CrossOver here is 25.0.1). Next step proposed to the owner: a
full stock 26.3 build from `runtime/build/cx26-x64` (`make -j12`, Unix and PE sides), run
Steam with it on a clone of `env-cx` (`cp -cR`). Black → upstream regression since 25, fix
in Wine; draws → swap stock `ntdll.so`/`wineserver` into Recall's engine one at a time.

**Update (03:35): it's upstream.** A full stock CrossOver 26.3 Wine build
(`runtime/build/cx26-x64`, `make -j12`, built clean) runs Steam on `env-stock` (an APFS clone
of `env-cx`) with the same black box: the login window ("Sign in to", 1400x880 at 200%) is
created and shown, but draws black. Run it with
`env -i ... WINEPREFIX=~/RecallCS2-spike/env-stock DYLD_FALLBACK_LIBRARY_PATH=/usr/local/lib:/usr/lib runtime/build/cx26-x64/wine 'C:\Program Files (x86)\Steam\steam.exe' -cef-disable-gpu -cef-disable-gpu-compositing -no-cef-sandbox`
(FreeType/GnuTLS come from Intel Homebrew). CrossOver 25.0.1's Wine draws it. So the bug
is a regression in Wine between CrossOver 25 and 26.3, not in Recall's patches or DXMT.
Next: find the change. Candidates are the win32u/winemac window-surface and OpenGL rework
in Wine 10.x (the trace shows the new `win32u_wgl*`/`opengl_drawable` code). Options:
compare CrossOver 25's sources (`crossover-sources-25.0.1.tar.gz`, same URL pattern) for
`dlls/winemac.drv` and `dlls/win32u` surface code, or bisect with mixed builds.

**Update (03:45): known Wine 11 bug, and a workaround in test.** Same report on the same
engine: https://github.com/gauthierpiarrette/highball/issues/282. On Wine 11, Steam's browser
draws black whenever it runs with the GPU off (`--disable-gpu`, which our `-cef-disable-gpu`
forced, and which Steam also adds itself unless `HKCU\Software\Valve\Steam`
`GPUAccelWebViewsV3`=1). With the GPU on it draws, but on Recall's DXMT the browser can't make
its swap chain (`EGL_BAD_ALLOC`, `SwapChain11.cpp:636`): Chrome presents into a child
window, and this DXMT (no `DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN`, pre-Wine-11 view lookup, see
https://github.com/notpop/steam-on-m1-wine docs/dxmt-diagnosis.md) can't find its view.
Workaround being tested: `scripts/steam_wined3d.sh install runtime/build/cx26-x64` puts the
stock 26.3 `d3d11/dxgi/d3d10core` (builtin marker renamed) in `bin/cef/cef.win64`, sets
`AppDefaults\steamwebhelper.exe\DllOverrides` to native, and sets `GPUAccelWebViewsV3`=1.
Steam must be launched **without** `WINEDLLOVERRIDES` forcing d3d11/dxgi builtin (the env var
beats AppDefaults), and without `-cef-disable-gpu`; flags `-cef-in-process-gpu -no-cef-sandbox`.
Result: webhelper_gpu.txt shows `ANGLE (Apple, Apple M2 Max ... Direct3D11 ... level_9_3)`
`*ACTIVE*`, no swap chain errors. Visual check pending (owner's screen was locked).
If it draws: for the app, ship Wine's own d3d11/dxgi for steamwebhelper only (and keep
`WINEDLLOVERRIDES` out of Steam's environment; set DXMT for games via registry or per-game
AppDefaults instead), then re-check that games launched from that Steam still use DXMT.

**Update (04:05): Steam's UI draws on Recall's engine.** What works:
`scripts/webhelper_wrapper.c` built with llvm-mingw
(`x86_64-w64-mingw32-clang -O2 -municode -mwindows`) into `runtime/build/wrapper/steamwebhelper.exe`,
installed over `bin/cef/cef.win64/steamwebhelper.exe` with the original renamed
`steamwebhelper_real.exe`. It adds `--in-process-gpu` plus `WEBHELPER_EXTRA_ARGS`; the working
value is `--use-angle=vulkan` (ANGLE on winevulkan/MoltenVK, inside the process that owns the
window). Also needed: `GPUAccelWebViewsV3`=1, Steam launched with `-noverifyfiles` (otherwise
its bootstrapper restores the 7.4 MB original), no `-cef-disable-gpu`, and no forced
`WINEDLLOVERRIDES` d3d entries in Steam's environment. The wined3d DLL copies are not needed
for this path (still installed from the earlier test; `scripts/steam_wined3d.sh remove`, and
delete the `AppDefaults\steamwebhelper_real.exe` key). Dead ends on the way: wined3d with GPU on
(separate GPU process can't present into another process's window; in-process it is capped at
feature level 9_3 = GLES 2, Chrome wants GLES 3), `CX_FWD_COMPAT_GL_CTX=1`, wined3d Vulkan
renderer, `-cef-single-process` (ignored by Steam), Wine virtual desktop (not in winemac).
Remaining: the Store page's web view is black while Steam's own UI draws; check Library and
other tabs. Capture only Steam's window with `screencapture -l <CGWindowID>` (find it with a
`CGWindowListCopyWindowInfo` script), not the whole screen.

Earlier reasoning: reading Recall's Wine patches found nothing that changes ordinary windows (canvas code is
gated on an active canvas). So the plan, approved by the owner, is to rebuild only the Mac
driver and bisect:

1. Source: `runtime/downloads/crossover-sources-26.3.0.tar.gz` (149 MB, from
   https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz;
   download log `runtime/downloads/curl.log`). Wine is the `sources/wine` subtree.
   `bison` 3.x from Intel Homebrew (`/usr/local`, log `runtime/downloads/brew-bison.log`);
   macOS's bison 2.3 is too old.
2. Configure that Wine for x86_64 (the engine runs under Rosetta: `arch -x86_64`, clang
   `-arch x86_64`, Homebrew at `/usr/local`), `--without-mingw` is fine since only a Unix
   library is needed, then build just `dlls/winemac.drv/winemac.so` (plus whatever
   `tools/` and generated headers it needs).
3. Build it **unpatched** first. Back up `~/RecallCS2-spike/engine/lib/wine/x86_64-unix/winemac.so`,
   drop the new one in (ad-hoc `codesign --force -s -`), launch Steam on Recall's engine
   (`SPIKE_ENV=env-cx scripts/cs2_spike.sh steam`) and ask the owner whether the window draws.
   - Draws → apply `patches/wine-v1-canvas.patch`, `wine-mouselook.patch`,
     `wine-winemac-activation.patch` one at a time (that order) to find the culprit.
   - Still black → the cause is outside winemac (win32u, or Recall's build recipe); compare
     `scripts/build_wine_native.py`'s other components or the Phase 2 configure options.
4. Fix: keep the guilty behaviour to the game's own windows, rebuild, then re-check Deadlock
   (fullscreen, mouse, FPS) on the patched engine.

Caveat: Recall's shipped `winemac.so` was linked by its own Phase 2 recipe
(`scripts/build_mouselook_driver.py`, needs `runtime/phase-2`, absent here). A driver from a
fresh configure should load against the shipped `win32u`/`ntdll` since the source is the
same, but if it crashes on load, check that first.

## After the black window

- Install and test CS2 the same way as Deadlock (`cs2` command).
- Confirm the lag spikes are shader compilation (second session smoother?).
- Then Phase 1 (identity: name, bundle ID, data folder, update feed, so it never collides
  with the real Recall; `AppLocation.swift` trashes same-identifier apps) and Phase 2 (Steam
  instead of Battle.net in `scripts/portable_setup.m`, per-game profiles for CS2/Deadlock).
- Open owner decisions: product name; CS2-only vs. Source 2 launcher (owner leaned to
  supporting Deadlock too).

## MacVolvo port (2026-10-13, 04:30)

The owner asked for a shippable app named **MacVolvo**; the GitHub repo is renamed to
`haeli05/MacVolvo` (local folder still `recallcs2`). Done, all uncommitted:
- Identity: `app/Sources/Brand.swift`, bundle id `app.macvolvo.launcher`, data folder
  `~/Library/Application Support/MacVolvo`, marker `.macvolvo-owner`, `scripts/build_native_app.py`
  (`APP_NAME`, build 1, Steam helper stand-in compiled into `Resources/steamwebhelper.exe`,
  Overwatch pipeline helper no longer built), `scripts/build_release_dmg.py`.
- `app/Resources/release.json`: version 0.1.0, Recall 1.3.0 runtime unchanged
  (`runtime/downloads/runtime.tar.gz`, from the Recall-1.3.0.dmg GitHub release), Steam's
  `SteamSetup.exe` pinned (`7d3654…2bcb`). New `AppIcon.png`, `Wordmark*.png`.
- Worker: `scripts/portable_steam.h` + edits in `portable_setup.m`, `portable_session.h`,
  `portable_preferences.h` (see `app/ARCHITECTURE.md`, "MacVolvo" section).
- App: game picker (CS2 / Deadlock), Steam wording, Overwatch settings removed, author
  promotion removed, About credits Recall.
- Build: `python3 scripts/build_native_app.py --output runtime/build/release/MacVolvo.app`
  (unsigned; pass `--identity "Developer ID Application: …"` to sign, then
  `scripts/build_release_dmg.py` with a `macvolvo-notary` notarytool profile).

Test state: the spike's `env-cx` was moved to `~/Library/Application Support/MacVolvo/environment`
(with `environment-owned.json`), runtime installed and `prepare` run through the worker CLI;
`status` shows Steam and Deadlock installed. `launch --game deadlock` started Steam with the
fix (`steamwebhelper_real.exe` running) but Deadlock had not started after 3+ minutes while the
owner's screen was locked; Steam logged nothing after startup. Next: look at Steam's window
after unlock (dialog?), compare with the spike, which used `-silent` and `-insecure`.
To undo the move: `mv ~/Library/Application\ Support/MacVolvo/environment ~/RecallCS2-spike/env-cx`.

**Update (04:45): process pile-up found and fixed.** That launch left dozens of
`steamwebhelper_real.exe` processes (macOS hit its process limit: "fork failed"). Steam logged
`Failed creating offscreen shared JS context` and kept restarting its helper; each time it
killed the wrapper, which orphaned the real browser. Likely trigger: the screen was locked,
so the Vulkan-drawn browser had no surface (the same setup worked unlocked). Fix in
`scripts/webhelper_wrapper.c`: the real helper runs in a job object with
`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, so it ends with the wrapper (tested under Wine by
killing the wrapper: the child ended). App rebuilt. Still to verify with the screen
unlocked: Steam's window and `launch --game deadlock` from the app.

**Update (11:05): the real cause of the pile-up.** Not the locked screen: the environment held
the spike's older wrapper as `steamwebhelper.exe`; the app's wrapper had a different hash, so
the worker took the old wrapper for Steam's helper and moved it over `steamwebhelper_real.exe`
(a wrapper starting itself, 1,300 processes in 80 s). Fixed: the worker recognizes a stand-in
by content (it contains "steamwebhelper_real.exe" in UTF-16), never moves one into the real
helper's place, and when the real helper is missing removes both and lets Steam's startup
check restore it (event `steam_helper_restoring`); the wrapper also refuses to run as
`steamwebhelper_real.exe`. Verified: repair start restored Steam's 7.4 MB helper, the next
start drew Steam's window with 6 helper processes. Same fix in `scripts/cs2_spike.sh`.
Also: Play screen has a full-size secondary "Open Steam" button beside Play.

## Deadlock launch repair (2026-10-13)

The owner reported startup crashes. Steam's retained history shows three launches
at 12:18–12:24 MYT with only `-steam -console`, each ending with `0xC0000409`.
A later MacVolvo launch supplying `-dx11 -novid` and display arguments exited
normally. The installed `Deadlock/game/citadel/cfg/boot.vcfg` explicitly selected
`DefaultRenderSystemOption` = `-vulkan`. An earlier nonfatal dump used DX11,
so the historical command line alone does not establish each run's backend.

With no game running, the installed boot file was backed up as
`boot.vcfg.macvolvo-backup`, then atomically changed to `-dx11`; verification
confirmed that only this value changed. This repairs Steam Library launches,
which bypass MacVolvo's existing `-dx11` argument. Explicit Steam launch options
can still override the default; none were present in the inspected configuration.

Source safeguard: `configureDeadlockRenderer()` in `scripts/portable_steam.h`
preserves other fields and the first backup, and `launchClient()` calls it before
the existing-Steam early return when no game runs. A write failure blocks an
explicit Deadlock launch with `game_renderer_write_failed`, but does not prevent
CS2 or Steam opening. The app presents a matching error in `SetupService.swift`.
These changes are included in the v0.9 local build described below.

Validation used the already-running Steam's ordinary `-applaunch 1422450`, without
an explicit renderer argument. The resulting process loaded
`rendersystemdx11.dll`, DXMT's `d3d11.dll` and `winemetal.dll`/`winemetal.so`.
The original Vulkan preference remains in the backup for rollback. Keep new
verification results scoped to startup; this does not establish in-match stability.

## MacVolvo v0.9 stability build (2026-10-13)

Owner requested app version **0.9**, per-game resolutions, Steam Properties
launch options, fixes for intermittent black startup and post-match mouse loss,
and investigation of CS2 combat spikes and the earlier sustained 4 FPS collapse.

Delivered app path: `runtime/build/release/MacVolvo.app`; source build retained at
`runtime/build/v0.9-final/MacVolvo.app`. Previous app is
`runtime/build/release/MacVolvo-before-v0.9.app`. Runtime: `phase2-20261013.1`,
archive SHA-256 `ce2530ec4a8656a6c7de71b4d72b7969c786b2a525295bf3014763f9235b2583`.
The isolated native driver build and ABI/dependency proof are under
`runtime/build/winemac-launch-fixes/`; derivation script and proof under
`runtime/build/launch-fixes/`. Only winemac.so differs from the base runtime;
all other file hashes and symlinks were verified. This is a local unsigned app
with an ad-hoc-signed replacement driver, not a published/notarized release.

Functional raw-motion timestamps no longer use the diagnostics-only clock
(which returned zero without WINEMAC_INPUT_STATS, suppressing pointer fallback).
Session discovery now accepts Windows and Unix process paths, then still
requires mapped files from the exact owned engine and prefix. Previously it
missed a live Steam process when ps reported its Unix executable path.

Steam is shut down normally before changing its cached localconfig LaunchOptions;
backups are private and unrelated VDF contents/user arguments are preserved.
Options apply to both games, with separate resolution/fullscreen settings,
DX11 and -nojoy, Deadlock -novid, and CS2 +fps_max 120 unless a user launch-option
cap already exists. Resolution choices include common ratios, display modes and
custom 640×480–16384×16384 sizes (fitted at launch when oversized).
An idle Steam may reopen to apply changes. UI explains that starting through
MacVolvo once syncs changed choices into Steam Properties.

Removed the inherited monitor that terminated Steam after 25 seconds; old `watch`
invocations are harmless no-ops. Cold launches use unique logs and a silent Steam
handoff. LaunchReadiness waits for a game window on game launches, preventing
early activation of Steam over fullscreen initialization.

CS2 gets four compiler workers versus Deadlock's inherited eight. This is a
contention mitigation, not a proven fix for combat spikes. The new opt-in
`diagnostic-launch --game cs2` includes shader/pipeline/resource and input-state
traces. `scripts/measure_macvolvo.py` adds bounded native counters with exact
session/PID-start admission. Run it with native ARM Python: Rosetta virtualizes
the clock timebase; the native reader now explicitly refuses translated Python.
The probe builds both architectures, and its tests use CLOCK_UPTIME_RAW because
macOS Python 3.9's monotonic clock has a process-relative origin.

Deadlock presented for roughly eight minutes in the first patched-runtime smoke
test; mapped files confirmed the replacement driver and DX11/DXMT. This does not
verify post-match camera recapture or every intermittent black-screen case.
The owner's later restart of the original app restored the old runtime; the
v0.9 delivery replaces that original path to keep the fix active. The old
runtime remains available as the prior version for rollback.

Audio help records the owner's successful 96 kHz workaround; no global audio
format is changed. Research, hypotheses and reproduction commands are in
`docs/CS2-PERFORMANCE-INVESTIGATION.md`. No renderer allocator patch is shipped.

Validation: 26 Python checks passed for raw input timing, Steam VDF preservation,
Windows/Unix process admission, PID reuse exclusion and native process counters;
Swift display and launch-readiness fixtures passed. Full native app build passed,
and all 228 bundle files were checked against the generated build manifest.
Version metadata and offline What's New both identify v0.9. CS2 combat behavior
and Deadlock mouse recapture after a match still require player verification on
this runtime, not the old app that was reopened during the earlier test.

Final check: the original app path runs v0.9 and the newly started Deadlock
process maps `phase2-20261013.1/lib/wine/x86_64-unix/winemac.so`. The owner
confirmed Esc and Cmd-Tab did not recover the earlier click-without-pan symptom.
No additional speculative input-state patch was made; test the corrected timer
across a complete match before declaring that symptom resolved. CS2 startup
produced frames on the new runtime; no fight or sustained-collapse trace has
yet established the remaining cause.
