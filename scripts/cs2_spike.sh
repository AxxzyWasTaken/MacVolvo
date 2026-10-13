#!/bin/bash
# Phase 0 feasibility spike: run Windows Steam and Counter-Strike 2 on Recall's existing
# Wine + DXMT engine, by hand, before any of the app is ported. See docs/PHASE0.md.
#
#   scripts/cs2_spike.sh engine /Applications/Recall.app   # take the engine from a Recall build
#   scripts/cs2_spike.sh init                               # create the Wine environment
#   scripts/cs2_spike.sh install-steam                      # download and run SteamSetup.exe
#   scripts/cs2_spike.sh steam                              # open Steam (sign in, install games)
#   scripts/cs2_spike.sh steam-cx                           # open Steam with CrossOver's own Wine
#                                                           #   (fallback; no longer needed)
#   scripts/cs2_spike.sh cs2                                # start CS2 through Steam, VAC off
#   scripts/cs2_spike.sh cs2-direct                         # start cs2.exe itself (Steam open)
#   scripts/cs2_spike.sh deadlock                           # start Deadlock the same way (same
#                                                           #   Source 2 engine as CS2)
#   scripts/cs2_spike.sh stop                               # end every Wine process
#   scripts/cs2_spike.sh audio off|on                       # Wine sound (off: Steam's browser
#                                                           #   crashes on Core Audio from Terminal)
#   scripts/cs2_spike.sh shell <wine args...>               # run anything in the environment
#
# Settings (environment variables):
#   SPIKE_ROOT   where everything lives (default ~/RecallCS2-spike; CS2 needs ~60 GB)
#   CS2_WIDTH / CS2_HEIGHT   fullscreen size (default 1920x1200, MacBook shape)
#   STEAM_FLAGS  extra Steam options (default -no-cef-sandbox)
#   WEBHELPER_EXTRA_ARGS  Chrome flags for Steam's browser (default --use-angle=vulkan)
#   MINGW_BIN    llvm-mingw's bin folder, to build the steamwebhelper wrapper
#   SPIKE_DEBUG=1  keep Wine's and DXMT's logs (slower)
#   SPIKE_MOUSELOOK=0  turn off Recall's raw mouse input, to compare
#   SPIKE_HUD=1  show Apple's Metal Performance HUD
#   SPIKE_GAMEMODE=0  start the game outside macOS Game Mode, to compare
#   SPIKE_ENV    the environment folder's name under SPIKE_ROOT (default environment)
#   CROSSOVER    CrossOver.app for steam-cx (default /Applications/CrossOver.app)
set -euo pipefail

ROOT="${SPIKE_ROOT:-$HOME/RecallCS2-spike}"
ENGINE="$ROOT/engine"
PREFIX="$ROOT/${SPIKE_ENV:-environment}"
LOGS="$ROOT/logs"
WIDTH="${CS2_WIDTH:-1920}"
HEIGHT="${CS2_HEIGHT:-1200}"
STEAM_FLAGS="${STEAM_FLAGS:--no-cef-sandbox}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MINGW_BIN="${MINGW_BIN:-$REPO/runtime/toolchains/llvm-mingw-20261006-ucrt-macos-universal/bin}"
WRAPPER="$REPO/runtime/build/wrapper/steamwebhelper.exe"
CEF_DIR="$PREFIX/drive_c/Program Files (x86)/Steam/bin/cef/cef.win64"
STEAM_SETUP_URL="https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
STEAM_EXE="$PREFIX/drive_c/Program Files (x86)/Steam/steam.exe"
DEADLOCK_EXE="$PREFIX/drive_c/Program Files (x86)/Steam/steamapps/common/Deadlock/game/bin/win64/deadlock.exe"
CS2_EXE="$PREFIX/drive_c/Program Files (x86)/Steam/steamapps/common/Counter-Strike Global Offensive/game/bin/win64/cs2.exe"

die() { echo "error: $*" >&2; exit 1; }
need_engine() { [ -x "$ENGINE/bin/wine" ] || die "no engine yet: run '$0 engine /path/to/Recall.app' first"; }

# The launch contract's environment (docs/candidate-parity-contract.json), with the game
# changed to cs2.exe, Overwatch's pipeline-cache warmup and Game Mode app left out, and a
# separate cache namespace so nothing from Overwatch is reused.
wine_env() {
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin
    export HOME="$ROOT/home" USER=player TMPDIR="$ROOT/tmp"
    export WINEPREFIX="$PREFIX" WINEARCH=win64
    export WINESERVER="$ENGINE/bin/wineserver" WINELOADER="$ENGINE/bin/wine"
    export CX_APPLEGPTK_LIBD3DSHARED_PATH="$ENGINE/lib/external/libd3dshared.dylib"
    export WINEMSYNC=1 WINEESYNC=0 ROSETTA_ADVERTISE_AVX=1 WINE_SIMULATE_WRITECOPY=1
    export CX_ACTIVE_GRAPHICS_BACKEND=dxmt CX_GRAPHICS_BACKEND=dxmt
    export WINEDLLOVERRIDES="d3d11,dxgi,d3d10core,winemetal=b;d3d12,nvapi64,nvngx="
    export DXMT_CANVAS_DRAWABLES=3 DXMT_CANVAS_OVERLAY=0 DXMT_USE_DEFAULT_METAL_CACHE=1
    export DXMT_PREPARE_SHADERS=1 DXMT_PIPELINE_CACHE_NAMESPACE=cs2-spike-v1
    export DXMT_SHADER_CACHE_PATH="$ROOT/cache/shaders" DXMT_PIPELINE_CACHE_PATH="$ROOT/cache/pipelines"
    export DXMT_CONFIG_FILE="Z:$(echo "$ROOT/dxmt.conf" | tr / '\\')"
    if [ "${SPIKE_MOUSELOOK:-1}" = 1 ]; then export WINEMAC_MOUSELOOK='cs2.exe;deadlock.exe'; else unset WINEMAC_MOUSELOOK; fi
    if [ "${SPIKE_GAMEMODE:-1}" = 1 ]; then export WINE_GAME_MODE=cs2.exe,deadlock.exe; else unset WINE_GAME_MODE; fi
    export WEBHELPER_EXTRA_ARGS="${WEBHELPER_EXTRA_ARGS:---use-angle=vulkan}"
    if [ "${SPIKE_HUD:-0}" = 1 ]; then export MTL_HUD_ENABLED=1; fi
    if [ "${SPIKE_DEBUG:-0}" = 1 ]; then
        export WINEDEBUG=err+all,fixme-all DXMT_LOG_LEVEL=info DXMT_LOG_PATH="$(echo "$LOGS" | sed 's|^|Z:|' | tr / '\\')"
    else
        export WINEDEBUG=-all DXMT_LOG_LEVEL=error DXMT_LOG_PATH=none
    fi
    mkdir -p "$ROOT/home" "$ROOT/tmp" "$ROOT/cache/shaders" "$ROOT/cache/pipelines" "$LOGS"
}

# macOS Game Mode: Recall's Wine restarts each program named in WINE_GAME_MODE from a loader
# copy at lib/wine/game-mode/<name>.app, a bundle that declares itself a game. The engine
# ships Overwatch.app only; make one per game from it, renamed and signed ad hoc with the
# same entitlements (JIT, unsigned memory, library validation off, microphone).
make_game_apps() {
    local dir="$ENGINE/lib/wine/game-mode" game app ents
    [ -d "$dir/Overwatch.app" ] || return 0
    for game in cs2 deadlock; do
        app="$dir/$game.app"
        [ -x "$app/Contents/MacOS/wine" ] && continue
        rm -rf "$app"; cp -R "$dir/Overwatch.app" "$app"
        plist="$app/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Set :CFBundleName $game" -c "Set :CFBundleIdentifier dev.recallcs2.spike.$game" \
            -c "Set :NSMicrophoneUsageDescription The game uses the microphone for voice chat." \
            -c "Delete :NSLocalNetworkUsageDescription" "$plist"
        ents="$ROOT/tmp/game-mode.entitlements"
        codesign -d --entitlements :- "$dir/Overwatch.app" > "$ents" 2>/dev/null
        codesign --force --sign - --options runtime --entitlements "$ents" "$app" 2>>"$LOGS/codesign.log" \
            || { echo "warning: couldn't sign $app (see $LOGS/codesign.log)"; rm -rf "$app"; }
    done
}

# Recall's renderer profile (config/dxmt-source60-1200.conf), keyed to cs2.exe at the chosen size.
write_dxmt_conf() {
    : > "$ROOT/dxmt.conf"
    for game in cs2.exe deadlock.exe; do cat >> "$ROOT/dxmt.conf" <<EOF
[$game]
d3d11.releaseShaderIR = True
d3d11.preferredMaxFrameRate = 0
d3d11.shaderCompilerThreads = 8
d3d11.shaderCompilerNormalPriority = True
dxgi.fullscreenCanvasWidth = $WIDTH
dxgi.fullscreenCanvasHeight = $HEIGHT
dxgi.nativeFullscreen = True
dxgi.maxFrameLatency = 1
dxgi.sharpPresentation = True
dxgi.presentPacing = True
dxgi.presentPacingMode = 3
dxgi.presentPacingTargetUs = 1000

EOF
    done
}

# Steam's window on Wine 11 (Recall's engine is CrossOver 26.3): with its browser's GPU off it
# draws black (https://github.com/gauthierpiarrette/highball/issues/282), and with the GPU on,
# Chrome's separate GPU process can't present into the browser's window (each Wine process has
# its own Cocoa windows) and Recall's DXMT can't find a Mac view for Chrome's child window. So:
# GPU web views on (GPUAccelWebViewsV3), and a stand-in steamwebhelper.exe
# (scripts/webhelper_wrapper.c) that runs the real one with --in-process-gpu plus
# WEBHELPER_EXTRA_ARGS (--use-angle=vulkan: ANGLE draws through MoltenVK). Steam then needs
# -noverifyfiles, or its startup check puts the original helper back. Echoes Steam's options.
steam_ui_fix() {
    if [ ! -f "$CEF_DIR/steamwebhelper.exe" ]; then
        echo "note: Steam hasn't finished its first update; its window may stay black until the next start" >&2
        return 0
    fi
    if [ ! -f "$WRAPPER" ] || [ "$REPO/scripts/webhelper_wrapper.c" -nt "$WRAPPER" ]; then
        [ -x "$MINGW_BIN/x86_64-w64-mingw32-clang" ] || die "need llvm-mingw to build the steamwebhelper wrapper (set MINGW_BIN; see docs/HANDOFF.md)"
        mkdir -p "$(dirname "$WRAPPER")"
        "$MINGW_BIN/x86_64-w64-mingw32-clang" -O2 -municode -mwindows -o "$WRAPPER" "$REPO/scripts/webhelper_wrapper.c" >&2
    fi
    # Anything else in the helper's place is Steam's own (first run, or an update): keep it as
    # the real one.
    # A stand-in names the real helper (UTF-16); Steam's own never does. Never move a stand-in
    # into the real one's place: it would start itself without end.
    standin() { python3 -I -c 'import sys;sys.exit(0 if "steamwebhelper_real.exe".encode("utf-16-le") in open(sys.argv[1],"rb").read() else 1)' "$1" 2>/dev/null; }
    if ! standin "$CEF_DIR/steamwebhelper.exe"; then
        mv -f "$CEF_DIR/steamwebhelper.exe" "$CEF_DIR/steamwebhelper_real.exe"
    elif [ ! -f "$CEF_DIR/steamwebhelper_real.exe" ] || standin "$CEF_DIR/steamwebhelper_real.exe"; then
        rm -f "$CEF_DIR/steamwebhelper.exe" "$CEF_DIR/steamwebhelper_real.exe"
        echo "note: Steam's own helper is missing; Steam restores it on this start (window may stay black once)" >&2
        return 0
    fi
    cmp -s "$WRAPPER" "$CEF_DIR/steamwebhelper.exe" || cp "$WRAPPER" "$CEF_DIR/steamwebhelper.exe"
    "$ENGINE/bin/wine" reg add 'HKCU\Software\Valve\Steam' /v GPUAccelWebViewsV3 /t REG_DWORD /d 1 /f >>"$LOGS/steam-setup.log" 2>&1
    echo "-noverifyfiles"
}

run_wine() { # run_wine <log name> <args...>: in the background, output to logs/<name>.log
    local log="$LOGS/$1.log"; shift
    echo "→ wine $*   (log: $log)"
    "$ENGINE/bin/wine" "$@" >>"$log" 2>&1 &
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
engine)
    app="${1:-/Applications/Recall.app}"
    archive="$app/Contents/Resources/runtime.tar.gz"
    [ -f "$archive" ] || die "no runtime archive at $archive (download Recall from https://github.com/AsherJN/recall/releases/latest)"
    rm -rf "$ROOT/engine.tmp"; mkdir -p "$ROOT/engine.tmp"
    echo "→ extracting $archive"
    tar -xzf "$archive" -C "$ROOT/engine.tmp"
    wine="$(find "$ROOT/engine.tmp" -maxdepth 4 -path '*/bin/wine' -type f | head -1)"
    [ -n "$wine" ] || die "the archive has no bin/wine"
    rm -rf "$ENGINE"; mv "$(dirname "$(dirname "$wine")")" "$ENGINE"; rm -rf "$ROOT/engine.tmp"
    xattr -dr com.apple.quarantine "$ENGINE" 2>/dev/null || true
    mkdir -p "$ROOT/tmp" "$LOGS"; make_game_apps
    echo "✓ engine at $ENGINE"
    ;;
init)
    need_engine; wine_env; write_dxmt_conf
    [ -e /Library/Apple/usr/libexec/oah/libRosettaRuntime ] || die "Rosetta isn't installed: run 'softwareupdate --install-rosetta --agree-to-license'"
    echo "→ creating the Wine environment at $PREFIX"
    "$ENGINE/bin/wine" wineboot.exe -u >>"$LOGS/wineboot.log" 2>&1
    "$ENGINE/bin/wineserver" -w
    "$ENGINE/bin/wine" reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /t REG_SZ /d Y /f >>"$LOGS/wineboot.log" 2>&1
    # 200% Windows scaling to go with Retina mode: Steam's window keeps its size, text stays sharp.
    "$ENGINE/bin/wine" reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d 192 /f >>"$LOGS/wineboot.log" 2>&1
    # Steam's browser crashes on Wine's Core Audio when run from Terminal (mmdevapi assert);
    # start with sound off. 'audio on' to try again.
    "$ENGINE/bin/wine" reg add 'HKCU\Software\Wine\Drivers' /v Audio /t REG_SZ /d '' /f >>"$LOGS/wineboot.log" 2>&1
    "$ENGINE/bin/wineserver" -w
    echo "✓ environment ready"
    ;;
install-steam)
    need_engine; wine_env
    setup="$ROOT/downloads/SteamSetup.exe"; mkdir -p "$ROOT/downloads"
    [ -f "$setup" ] || curl --fail --location --proto =https -o "$setup" "$STEAM_SETUP_URL"
    echo "→ installing Steam (silent)"
    "$ENGINE/bin/wine" "$setup" /S >>"$LOGS/steam-setup.log" 2>&1 || true
    "$ENGINE/bin/wineserver" -w
    [ -f "$STEAM_EXE" ] && echo "✓ Steam installed" || die "steam.exe not found; see $LOGS/steam-setup.log"
    ;;
steam)
    need_engine; wine_env; write_dxmt_conf
    [ -f "$STEAM_EXE" ] || die "Steam isn't installed: run '$0 install-steam'"
    fix="$(steam_ui_fix)"
    # shellcheck disable=SC2086
    run_wine steam "$STEAM_EXE" $fix $STEAM_FLAGS
    ;;
steam-cx)
    # Fallback from before steam_ui_fix: CrossOver 25's Wine draws Steam's window with the GPU
    # off. Stop it before using Recall's engine ('stop' doesn't reach CrossOver's wineserver:
    # quit Steam from its menu, or run this with 'stop').
    cx="${CROSSOVER:-/Applications/CrossOver.app}/Contents/SharedSupport/CrossOver/bin"
    [ -x "$cx/wineloader" ] || die "CrossOver not found at ${CROSSOVER:-/Applications/CrossOver.app}"
    [ -f "$STEAM_EXE" ] || die "Steam isn't installed: run '$0 install-steam'"
    if [ "${1:-}" = stop ]; then WINEPREFIX="$PREFIX" "$cx/wineserver" -k || true; echo "✓ stopped"; exit 0; fi
    mkdir -p "$ROOT/home" "$ROOT/tmp" "$LOGS"
    echo "→ CrossOver wine steam.exe   (log: $LOGS/steam-cx.log)"
    env -i PATH=/usr/bin:/bin HOME="$ROOT/home" USER="$USER" TMPDIR="$ROOT/tmp" WINEPREFIX="$PREFIX" \
        WINEDEBUG=-all WINESERVER="$cx/wineserver" WINELOADER="$cx/wineloader" \
        "$cx/wineloader" 'C:\Program Files (x86)\Steam\steam.exe' \
        -cef-disable-gpu -cef-disable-gpu-compositing -no-cef-sandbox >>"$LOGS/steam-cx.log" 2>&1 &
    ;;
cs2)
    need_engine; wine_env; write_dxmt_conf; make_game_apps
    [ -f "$STEAM_EXE" ] || die "Steam isn't installed: run '$0 install-steam'"
    fix="$(steam_ui_fix)"
    # -silent: Steam starts in the background. -insecure: VAC off for the whole spike. Never
    # test on your main account.
    # shellcheck disable=SC2086
    run_wine cs2 "$STEAM_EXE" $fix $STEAM_FLAGS -silent -applaunch 730 -insecure -nojoy -fullscreen -w "$WIDTH" -h "$HEIGHT" "$@"
    ;;
deadlock)
    need_engine; wine_env; write_dxmt_conf; make_game_apps
    [ -f "$STEAM_EXE" ] || die "Steam isn't installed: run '$0 install-steam'"
    [ -f "$DEADLOCK_EXE" ] || echo "note: Deadlock isn't installed yet (expected $DEADLOCK_EXE)"
    fix="$(steam_ui_fix)"
    # Deadlock is Valve's too (app 1422450, deadlock.exe) and also uses VAC: alt account.
    # shellcheck disable=SC2086
    run_wine deadlock "$STEAM_EXE" $fix $STEAM_FLAGS -silent -applaunch 1422450 -insecure -nojoy -fullscreen -w "$WIDTH" -h "$HEIGHT" -dx11 "$@"
    ;;
cs2-direct)
    need_engine; wine_env; write_dxmt_conf; make_game_apps
    [ -f "$CS2_EXE" ] || die "CS2 isn't installed (expected $CS2_EXE)"
    run_wine cs2-direct "$CS2_EXE" -insecure -nojoy -fullscreen -w "$WIDTH" -h "$HEIGHT" "$@"
    ;;
audio)
    need_engine; wine_env
    case "${1:-}" in
        off) "$ENGINE/bin/wine" reg add 'HKCU\Software\Wine\Drivers' /v Audio /t REG_SZ /d '' /f >>"$LOGS/audio.log" 2>&1 ;;
        on)  "$ENGINE/bin/wine" reg delete 'HKCU\Software\Wine\Drivers' /v Audio /f >>"$LOGS/audio.log" 2>&1 || true ;;
        *)   die "usage: $0 audio off|on" ;;
    esac
    "$ENGINE/bin/wineserver" -w
    echo "✓ audio $1 (applies to the next launch)"
    ;;
stop)
    need_engine; wine_env
    "$ENGINE/bin/wineserver" -k || true
    echo "✓ stopped"
    ;;
shell)
    need_engine; wine_env
    exec "$ENGINE/bin/wine" "$@"
    ;;
*)
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
