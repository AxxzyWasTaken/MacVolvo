#!/usr/bin/env python3
"""Set SCP: Secret Laboratory's graphics backend in macOS Steam's launch options (NotProton).

usage: macsl_steam_options.py <backend>   (dxmt | d3dmetal)
NotProton passes CX_GRAPHICS_BACKEND from the launch options to CrossOver's Wine, so
"CX_GRAPHICS_BACKEND=dxmt %command%" picks DXMT for this game only, whichever CrossOver
build NotProton maps the game to. Steam keeps its own copy while running and rewrites the
file on exit, so this refuses while macOS Steam is open. Keeps a one-time backup.
"""
import glob, os, re, shutil, subprocess, sys

APP = "700330"
STEAM = os.environ.get("MACSL_STEAM_DIR") or os.path.expanduser("~/Library/Application Support/Steam")

def tokens(text):
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"|([{}])|//[^\n]*', text):
        if m.group(2):
            yield m.group(2), m.start(), m.end()
        elif m.group(1) is not None:
            yield "str", m.start(), m.end()

def find_app(text):
    """Return (open_brace_end, close_brace_start) of .../apps/700330 { }."""
    stack, key = [], None  # key: last key read, waiting for its value
    for kind, s, e in tokens(text):
        if kind == "str":
            if key is None:
                key = text[s + 1:e - 1]
            else:
                key = None  # string value: pair done
        elif kind == "{":
            stack.append((key or "", e)); key = None
        elif kind == "}":
            if not stack:
                return None
            name, start = stack.pop()
            if name == APP and stack and stack[-1][0].lower() == "apps":
                return start, s
            key = None
    return None

def merge(current, backend):
    want = f"CX_GRAPHICS_BACKEND={backend}"
    if re.search(r"(^|\s)CX_GRAPHICS_BACKEND=\S*", current):
        return re.sub(r"(^|\s)CX_GRAPHICS_BACKEND=\S*", lambda m: m.group(1) + want, current, count=1)
    if "%command%" in current:
        return f"{want} {current}".strip()
    return f"{want} %command% {current}".strip()

def main():
    backend = sys.argv[1]
    if subprocess.run(["pgrep", "-x", "steam_osx"], capture_output=True).returncode == 0:
        print("macOS Steam is running; will apply after it quits"); return 2
    changed = 0
    for path in glob.glob(os.path.join(STEAM, "userdata", "*", "config", "localconfig.vdf")):
        text = open(path, encoding="utf-8", errors="surrogateescape").read()
        span = find_app(text)
        if not span:
            continue  # this account never touched the game
        start, end = span
        body = text[start:end]
        m = re.search(r'"LaunchOptions"\s+"((?:[^"\\]|\\.)*)"', body)
        if m:
            new_val = merge(m.group(1), backend)
            if new_val == m.group(1):
                continue
            body = body[:m.start(1)] + new_val + body[m.end(1):]
        else:
            indent = re.search(r'\n([\t ]*)"', body)
            indent = indent.group(1) if indent else "\t\t\t\t\t\t"
            body = body.rstrip("\t ") + f'{indent}"LaunchOptions"\t\t"{merge("", backend)}"\n' + body[len(body.rstrip("\t ")):]
        backup = path + ".macsl-backup"
        if not os.path.exists(backup):
            shutil.copy2(path, backup)
        tmp = path + ".macsl-tmp"
        open(tmp, "w", encoding="utf-8", errors="surrogateescape").write(text[:start] + body + text[end:])
        os.replace(tmp, path)
        changed += 1
        shown = re.search(r'"LaunchOptions"\s+"([^"]*)"', body)
        print("Steam launch options for %s: %s" % (APP, shown.group(1) if shown else "?"))
    if not changed:
        print("Steam launch options already set")
    return 0

if __name__ == "__main__":
    sys.exit(main())
