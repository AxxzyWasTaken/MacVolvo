#!/bin/bash
# macsl-crossover: run SCP: Secret Laboratory with the graphics backend you choose, in your
# existing CrossOver bottles (Rosetta or ARM64/FEX) and in macOS Steam through NotProton.
#
#   macsl-crossover status          the backend in each bottle and in Steam's launch options
#   macsl-crossover dxmt            use CrossOver's DXMT for SCP:SL everywhere
#   macsl-crossover d3dmetal        use D3DMetal (CrossOver's default; Rosetta bottles only)
#   macsl-crossover ensure          re-apply the chosen backend if something reset it (used by auto)
#   macsl-crossover auto on         re-apply automatically: at login, every 30 min, and whenever a
#                                   bottle config, Steam's launch options or CrossOver change
#   macsl-crossover auto off        stop doing that
#   macsl-crossover play [bottle]   launch SCP:SL in a CrossOver bottle
#   macsl-crossover undo            auto off, and restore every file from this tool's first backups
#
# Bottles: every CrossOver bottle that has SCP:SL installed, or MACSL_BOTTLES="name1 name2".
# Backend changes only reach programs started afterwards, so `dxmt`/`d3dmetal` offer to
# restart CrossOver's Steam. macOS Steam must be closed for its launch options to change
# (it rewrites them on exit); with auto on they're applied as soon as it quits.
# Nothing inside CrossOver.app or NotProton is modified.
set -euo pipefail

BOTTLES_DIR="$HOME/Library/Application Support/CrossOver/Bottles"
GAME_REL="drive_c/Program Files (x86)/Steam/steamapps/common/SCP Secret Laboratory/SCPSL.exe"
STEAM='C:\Program Files (x86)\Steam\steam.exe'
PREFS="$HOME/.config/macsl"; PREF="$PREFS/backend"
SHARE="$HOME/.local/share/macsl"
AGENT="$HOME/Library/LaunchAgents/app.macsl.ensure.plist"
HERE="$(cd "$(dirname "$(readlink "$0" 2>/dev/null || echo "$0")")" && pwd)"
STEAMOPTS="$HERE/macsl_steam_options.py"
[ -f "$STEAMOPTS" ] || STEAMOPTS="$SHARE/macsl_steam_options.py"
STEAM_USERDATA="$HOME/Library/Application Support/Steam/userdata"

CXAPP="${MACSL_CROSSOVER:-}"
if [ -z "$CXAPP" ]; then
  for a in "/Applications/CrossOver.app" "/Applications/CrossOver Preview.app" "$HOME/Applications/CrossOver.app" "$HOME/Applications/CrossOver Preview.app"; do
    [ -x "$a/Contents/SharedSupport/CrossOver/bin/wine" ] && { CXAPP="$a"; break; }
  done
fi
WINE="${CXAPP:+$CXAPP/Contents/SharedSupport/CrossOver/bin/wine}"

# Wine must not start with a cwd in Desktop/Documents/Downloads: the wineserver opens the cwd,
# macOS shows a privacy prompt, and every Wine process (including a running game) stalls.
cd "$HOME"

bottles() {
  if [ -n "${MACSL_BOTTLES:-}" ]; then printf '%s\n' $MACSL_BOTTLES; return; fi
  for d in "$BOTTLES_DIR"/*/; do
    d=${d%/}; [ -f "$d/cxbottle.conf" ] && [ -f "$d/$GAME_REL" ] && basename "$d"
  done
}
conf() { echo "$BOTTLES_DIR/$1/cxbottle.conf"; }
arch() { sed -n 's/^"WineArch" *= *"\(.*\)"/\1/p' "$(conf "$1")" | tail -1; }
backend() { sed -n 's/^"CX_GRAPHICS_BACKEND" *= *"\(.*\)"/\1/p' "$(conf "$1")" | tail -1; }
preferred() { cat "$PREF" 2>/dev/null || echo dxmt; }
steam_backend() {
  grep -h -o 'CX_GRAPHICS_BACKEND=[a-z0-9]*' "$STEAM_USERDATA/"*/config/localconfig.vdf 2>/dev/null | head -1 | cut -d= -f2
}

set_backend() {  # bottle backend
  local b=$1 want=$2 c; c=$(conf "$b")
  # D3DMetal is x86-64 only; ARM64 (FEX) bottles stay on DXMT.
  if [ "$want" = d3dmetal ] && [ "$(arch "$b")" = arm64 ]; then want=dxmt; fi
  [ "$(backend "$b")" = "$want" ] && return 0
  [ -f "$c.macsl-backup" ] || cp -p "$c" "$c.macsl-backup"
  python3 - "$c" "$want" <<'EOF'
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
}

game_running() { pgrep -f 'SCPSL\.exe' >/dev/null; }
steam_running() { pgrep -f '^C:.Program Files .x86..Steam.steam\.exe' >/dev/null; }
need_cx() { [ -n "$CXAPP" ] || { echo "CrossOver not found (set MACSL_CROSSOVER=/path/to/CrossOver.app)"; exit 1; }; }

restart_steam() {  # bottle
  need_cx
  if game_running; then echo "Close SCP: Secret Laboratory first."; exit 1; fi
  if steam_running; then
    echo "Closing CrossOver's Steam so it picks up the new settings..."
    "$WINE" --bottle "$1" --no-wait "$STEAM" -shutdown >/dev/null 2>&1 || true
    for _ in $(seq 1 60); do steam_running || break; sleep 1; done
    sleep 3
  fi
}

play() {  # [bottle]
  need_cx
  local b=${1:-$(bottles | head -1)}
  [ -n "$b" ] || { echo "No CrossOver bottle with SCP:SL found."; exit 1; }
  if game_running; then echo "SCP: Secret Laboratory is already running."; exit 0; fi
  echo "Starting SCP: Secret Laboratory ($(backend "$b")) in bottle '$b'..."
  "$WINE" --bottle "$b" --no-wait "$STEAM" -silent -applaunch 700330 >/dev/null 2>&1
}

ask_restart() {
  if steam_running && [ -t 0 ]; then
    read -r -p "Restart CrossOver's Steam now and launch the game? [Y/n] " a
    case "${a:-y}" in [Yy]*) b=$(bottles | head -1); restart_steam "$b"; play "$b" ;; *) echo "Takes effect the next time Steam starts." ;; esac
  fi
}

ensure() {
  local want; want=$(preferred)
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    set_backend "$b" "$want"
    echo "CrossOver bottle '$b' ($(arch "$b")): $(backend "$b")"
  done < <(bottles)
  # NotProton: D3DMetal only exists in its Rosetta tools; it drops d3dmetal under FEX by itself.
  [ -f "$STEAMOPTS" ] && { python3 "$STEAMOPTS" "$want" || true; }
}

choose() { mkdir -p "$PREFS"; echo "$1" > "$PREF"; ensure; ask_restart; }

auto_on() {
  mkdir -p "$SHARE" "$HOME/Library/LaunchAgents"
  # launchd can't read ~/Documents (privacy-protected), so it runs a copy from ~/.local/share.
  cp -p "$HERE/macsl-crossover.sh" "$HERE/macsl_steam_options.py" "$SHARE/"
  watch=("$BOTTLES_DIR" "/Applications/CrossOver.app" "/Applications/CrossOver Preview.app"
         "$HOME/Library/Application Support/Steam/compatibilitytools.d")
  while IFS= read -r b; do [ -n "$b" ] && watch+=("$(conf "$b")"); done < <(bottles)
  for f in "$STEAM_USERDATA/"*/config/localconfig.vdf; do [ -f "$f" ] && watch+=("$f"); done
  python3 - "$AGENT" "$SHARE/macsl-crossover.sh" "$HOME/Library/Logs/macsl-ensure.log" "${watch[@]}" <<'EOF'
import plistlib, sys
agent, script, log, *watch = sys.argv[1:]
plistlib.dump({"Label": "app.macsl.ensure", "ProgramArguments": ["/bin/bash", script, "ensure"],
               "WatchPaths": watch, "RunAtLoad": True, "StartInterval": 1800, "ThrottleInterval": 15,
               "StandardOutPath": log, "StandardErrorPath": log}, open(agent, "wb"))
EOF
  launchctl bootout "gui/$(id -u)/app.macsl.ensure" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$AGENT"
  echo "Auto on: '$(preferred)' is re-applied at login, every 30 minutes, and whenever a bottle, Steam's launch options or CrossOver change."
}

auto_off() {
  launchctl bootout "gui/$(id -u)/app.macsl.ensure" 2>/dev/null || true
  rm -f "$AGENT"; echo "Auto off."
}

undo() {
  auto_off; rm -f "$PREF"
  for c in "$BOTTLES_DIR"/*/cxbottle.conf.macsl-backup; do
    [ -f "$c" ] || continue
    mv "$c" "${c%.macsl-backup}"; echo "Restored ${c%.macsl-backup}"
  done
  for f in "$STEAM_USERDATA/"*/config/localconfig.vdf.macsl-backup; do
    [ -f "$f" ] || continue
    if pgrep -x steam_osx >/dev/null; then echo "Quit macOS Steam, then run undo again to restore its launch options."; break; fi
    mv "$f" "${f%.macsl-backup}"; echo "Restored ${f%.macsl-backup}"
  done
  ask_restart
}

case "${1:-status}" in
  status)   echo "Chosen backend: $(preferred)"
            echo "CrossOver: ${CXAPP:-not found}"
            while IFS= read -r b; do [ -n "$b" ] && echo "  bottle '$b' ($(arch "$b")): $(backend "$b")"; done < <(bottles)
            echo "macOS Steam / NotProton launch options: $(steam_backend || true)"
            launchctl print "gui/$(id -u)/app.macsl.ensure" >/dev/null 2>&1 && echo "Auto: on" || echo "Auto: off" ;;
  dxmt)     choose dxmt ;;
  d3dmetal) choose d3dmetal ;;
  ensure)   ensure ;;
  auto)     case "${2:-}" in on) auto_on ;; off) auto_off ;; *) echo "usage: macsl-crossover auto on|off"; exit 1 ;; esac ;;
  play)     play "${2:-}" ;;
  undo)     undo ;;
  *)        sed -n '2,22p' "$0"; exit 1 ;;
esac
