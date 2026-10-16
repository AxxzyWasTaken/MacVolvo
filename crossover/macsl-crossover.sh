#!/bin/bash
# macsl-crossover: run SCP: Secret Laboratory with the graphics backend you choose, in your
# existing CrossOver bottle and in macOS Steam through NotProton, without a separate install.
#
#   macsl-crossover status      show the backend in the bottle and in Steam's launch options
#   macsl-crossover dxmt        use CrossOver's DXMT for SCP:SL (CrossOver bottle + NotProton)
#   macsl-crossover d3dmetal    use D3DMetal (CrossOver's default)
#   macsl-crossover ensure      re-apply the chosen backend if something reset it (used by auto)
#   macsl-crossover auto on     re-apply automatically: at login, whenever the bottle config,
#                               Steam's launch options or CrossOver itself change (new versions)
#   macsl-crossover auto off    stop doing that
#   macsl-crossover play        launch SCP:SL in the CrossOver bottle
#   macsl-crossover undo        auto off, and restore the files from this tool's first backups
#
# Backend changes only reach programs started afterwards, so `dxmt`/`d3dmetal` offer to
# restart CrossOver's Steam. macOS Steam must be closed for its launch options to change
# (it rewrites them on exit); with auto on they're applied as soon as it quits.
# Nothing inside CrossOver.app or NotProton is modified.
set -euo pipefail

BOTTLE="${MACSL_BOTTLE:-Steamm}"
CXAPP="${MACSL_CROSSOVER:-}"
if [ -z "$CXAPP" ]; then
  for a in "/Applications/CrossOver.app" "/Applications/CrossOver Preview.app" "$HOME/Applications/CrossOver.app" "$HOME/Applications/CrossOver Preview.app"; do
    [ -x "$a/Contents/SharedSupport/CrossOver/bin/wine" ] && { CXAPP="$a"; break; }
  done
fi
[ -n "$CXAPP" ] || { echo "CrossOver not found (set MACSL_CROSSOVER=/path/to/CrossOver.app)"; exit 1; }
WINE="$CXAPP/Contents/SharedSupport/CrossOver/bin/wine"
BDIR="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE"
CONF="$BDIR/cxbottle.conf"
BACKUP="$CONF.macsl-backup"
PREFS="$HOME/.config/macsl"; PREF="$PREFS/backend"
SHARE="$HOME/.local/share/macsl"
AGENT="$HOME/Library/LaunchAgents/app.macsl.ensure.plist"
HERE="$(cd "$(dirname "$(readlink "$0" 2>/dev/null || echo "$0")")" && pwd)"
STEAMOPTS="$HERE/macsl_steam_options.py"
[ -f "$STEAMOPTS" ] || STEAMOPTS="$SHARE/macsl_steam_options.py"
STEAM='C:\Program Files (x86)\Steam\steam.exe'
[ -f "$CONF" ] || { echo "Bottle '$BOTTLE' not found (set MACSL_BOTTLE)"; exit 1; }

# Wine must not start with a cwd in Desktop/Documents/Downloads: the wineserver opens the cwd,
# macOS shows a privacy prompt, and every Wine process (including a running game) stalls.
cd "$HOME"

backend() { sed -n 's/^"CX_GRAPHICS_BACKEND" *= *"\(.*\)"/\1/p' "$CONF" | tail -1; }

preferred() { cat "$PREF" 2>/dev/null || echo dxmt; }
steam_backend() {
  grep -h -o 'CX_GRAPHICS_BACKEND=[a-z0-9]*' "$HOME/Library/Application Support/Steam/userdata/"*/config/localconfig.vdf 2>/dev/null | head -1 | cut -d= -f2
}
set_backend() {
  [ "$(backend)" = "$1" ] && return 0
  [ -f "$BACKUP" ] || cp -p "$CONF" "$BACKUP"
  python3 - "$CONF" "$1" <<'EOF'
import re, sys
path, value = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
line = f'"CX_GRAPHICS_BACKEND" = "{value}"'
if re.search(r'^"CX_GRAPHICS_BACKEND"\s*=.*$', text, re.M):
    text = re.sub(r'^"CX_GRAPHICS_BACKEND"\s*=.*$', line, text, count=1, flags=re.M)
elif "[EnvironmentVariables]" in text:
    text = text.replace("[EnvironmentVariables]", "[EnvironmentVariables]\n" + line, 1)
else:
    text = text.rstrip("\n") + "\n\n[EnvironmentVariables]\n" + line + "\n"
open(path, "w", encoding="utf-8").write(text)
EOF
  echo "Bottle '$BOTTLE' now uses: $(backend)"
}

game_running() { pgrep -f 'SCPSL\.exe' >/dev/null; }
steam_running() { pgrep -f '^C:.Program Files .x86..Steam.steam\.exe' >/dev/null; }

restart_steam() {
  if game_running; then echo "Close SCP: Secret Laboratory first."; exit 1; fi
  if steam_running; then
    echo "Closing Steam so it picks up the new settings..."
    "$WINE" --bottle "$BOTTLE" --no-wait "$STEAM" -shutdown >/dev/null 2>&1 || true
    for _ in $(seq 1 60); do steam_running || break; sleep 1; done
    sleep 3
  fi
}

play() {
  if game_running; then echo "SCP: Secret Laboratory is already running."; exit 0; fi
  echo "Starting SCP: Secret Laboratory ($(backend)) in bottle '$BOTTLE'..."
  "$WINE" --bottle "$BOTTLE" --no-wait "$STEAM" -silent -applaunch 700330 >/dev/null 2>&1
}

ask_restart() {
  if steam_running; then
    read -r -p "Restart Steam now and launch the game? [Y/n] " a
    case "${a:-y}" in [Yy]*) restart_steam; play ;; *) echo "Takes effect the next time Steam starts." ;; esac
  fi
}

ensure() {
  b=$(preferred)
  set_backend "$b" >/dev/null && echo "CrossOver bottle '$BOTTLE': $(backend)"
  python3 "$STEAMOPTS" "$b" || true
}

choose() {
  mkdir -p "$PREFS"; echo "$1" > "$PREF"
  ensure
  ask_restart
}

auto_on() {
  mkdir -p "$SHARE" "$HOME/Library/LaunchAgents"
  # launchd can't read ~/Documents (privacy-protected), so run a copy from ~/.local/share.
  cp -p "$HERE/macsl-crossover.sh" "$HERE/macsl_steam_options.py" "$SHARE/"
  watch=("$CONF" "/Applications/CrossOver.app" "/Applications/CrossOver Preview.app"
         "$HOME/Library/Application Support/Steam/compatibilitytools.d")
  for f in "$HOME/Library/Application Support/Steam/userdata/"*/config/localconfig.vdf; do [ -f "$f" ] && watch+=("$f"); done
  python3 - "$AGENT" "$SHARE/macsl-crossover.sh" "$HOME/Library/Logs/macsl-ensure.log" "${watch[@]}" <<'EOF'
import plistlib, sys
agent, script, log, *watch = sys.argv[1:]
plistlib.dump({"Label": "app.macsl.ensure", "ProgramArguments": ["/bin/bash", script, "ensure"],
               "WatchPaths": watch, "RunAtLoad": True, "StartInterval": 1800, "ThrottleInterval": 15,
               "StandardOutPath": log, "StandardErrorPath": log}, open(agent, "wb"))
EOF
  launchctl bootout "gui/$(id -u)/app.macsl.ensure" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$AGENT"
  echo "Auto on: the chosen backend ($(preferred)) is re-applied at login and whenever the bottle, Steam's launch options or CrossOver change."
}

auto_off() {
  launchctl bootout "gui/$(id -u)/app.macsl.ensure" 2>/dev/null || true
  rm -f "$AGENT"; echo "Auto off."
}

case "${1:-status}" in
  status)   echo "Chosen backend: $(preferred)"
            echo "CrossOver bottle '$BOTTLE' ($CXAPP): $(backend)"
            echo "macOS Steam / NotProton launch options: $(steam_backend || true)"
            launchctl print "gui/$(id -u)/app.macsl.ensure" >/dev/null 2>&1 && echo "Auto: on" || echo "Auto: off" ;;
  dxmt)     choose dxmt ;;
  d3dmetal) choose d3dmetal ;;
  ensure)   ensure ;;
  auto)     case "${2:-}" in on) auto_on ;; off) auto_off ;; *) echo "usage: macsl-crossover auto on|off"; exit 1 ;; esac ;;
  play)     play ;;
  undo)     auto_off; rm -f "$PREF"
            if [ -f "$BACKUP" ]; then cp -p "$BACKUP" "$CONF"; rm -f "$BACKUP"; echo "Restored cxbottle.conf. Backend: $(backend)"; fi
            for f in "$HOME/Library/Application Support/Steam/userdata/"*/config/localconfig.vdf.macsl-backup; do
              [ -f "$f" ] || continue
              if pgrep -x steam_osx >/dev/null; then echo "Quit macOS Steam, then run undo again to restore its launch options."; break; fi
              mv "$f" "${f%.macsl-backup}"; echo "Restored ${f%.macsl-backup}"
            done
            ask_restart ;;
  *)        sed -n '2,20p' "$0"; exit 1 ;;
esac
