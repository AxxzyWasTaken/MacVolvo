#!/bin/bash
# macsl-crossover: run SCP: Secret Laboratory in your existing CrossOver bottle with the
# graphics backend you choose, without a separate Steam install.
#
#   macsl-crossover status          show the bottle's backend
#   macsl-crossover dxmt            switch the bottle to CrossOver's DXMT backend
#   macsl-crossover d3dmetal        switch back to D3DMetal (CrossOver's default)
#   macsl-crossover play            (re)start Steam with the bottle's settings and launch SCP:SL
#   macsl-crossover undo            restore cxbottle.conf from the first backup this tool made
#
# Backend changes only take effect for programs started afterwards, so `dxmt`/`d3dmetal`
# offer to restart Steam. Nothing inside CrossOver.app is modified.
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
STEAM='C:\Program Files (x86)\Steam\steam.exe'
[ -f "$CONF" ] || { echo "Bottle '$BOTTLE' not found (set MACSL_BOTTLE)"; exit 1; }

# Wine must not start with a cwd in Desktop/Documents/Downloads: the wineserver opens the cwd,
# macOS shows a privacy prompt, and every Wine process (including a running game) stalls.
cd "$HOME"

backend() { sed -n 's/^"CX_GRAPHICS_BACKEND" *= *"\(.*\)"/\1/p' "$CONF" | tail -1; }

set_backend() {
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

case "${1:-status}" in
  status)   echo "Bottle: $BOTTLE  CrossOver: $CXAPP"; echo "Graphics backend: $(backend)"; [ -f "$BACKUP" ] && echo "Backup: $BACKUP" || true ;;
  dxmt)     set_backend dxmt; ask_restart ;;
  d3dmetal) set_backend d3dmetal; ask_restart ;;
  play)     play ;;
  undo)     [ -f "$BACKUP" ] || { echo "No backup to restore."; exit 1; }
            cp -p "$BACKUP" "$CONF"; rm -f "$BACKUP"; echo "Restored cxbottle.conf. Backend: $(backend)"; ask_restart ;;
  *)        sed -n '2,12p' "$0"; exit 1 ;;
esac
