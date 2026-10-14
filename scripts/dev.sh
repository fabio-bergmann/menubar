#!/usr/bin/env bash
# The "localhost" for this app. Builds the working tree, uncommitted edits
# included, as "Menubar Dev" and relaunches it whenever a source file
# changes. It has its own settings.
#
# Two copies would each ask macOS to hide a different set of icons, so the
# installed Menubar is quit while this runs and reopened when it stops.
#
# It runs from /Applications/Menubar Dev.app, removed again on Ctrl-C, like
# the installed app: macOS only honours its allowlist for apps there.
#
#   scripts/dev.sh     # leave it running in a terminal tab; Ctrl-C stops it
#
# A build that fails prints its errors and leaves the last good build running.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILT="$ROOT/build/Menubar Dev.app"
APP="/Applications/Menubar Dev.app"
BIN="$APP/Contents/MacOS/Menubar"
BUILD_LOG="$(mktemp -t menubar-dev)"
APP_LOG="$ROOT/build/dev.log"
TAIL_PID=""

app_running() { pgrep -f "$BIN" >/dev/null; }

stop_app() {
  pkill -f "$BIN" 2>/dev/null
  for _ in $(seq 1 20); do app_running || return 0; sleep 0.1; done
  pkill -9 -f "$BIN" 2>/dev/null
}

INSTALLED="/Applications/Menubar.app"
INSTALLED_WAS_RUNNING=""

cleanup() {
  stop_app
  rm -rf "$APP"
  [ -n "$INSTALLED_WAS_RUNNING" ] && open -g "$INSTALLED"
  [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null
  rm -f "$BUILD_LOG"
  echo
  echo "Stopped."
  exit 0
}
trap cleanup INT TERM HUP

# Changes whenever a file that shapes the build is edited, added or removed.
fingerprint() {
  find "$ROOT/Sources" "$ROOT/Support" "$ROOT/Package.swift" "$ROOT/scripts/build-app.sh" \
    -type f -exec stat -f '%m %N' {} + | shasum | cut -d' ' -f1
}

rebuild() {
  local started=$SECONDS
  if MENUBAR_VARIANT=dev bash "$ROOT/scripts/build-app.sh" >"$BUILD_LOG" 2>&1; then
    stop_app
    rm -rf "$APP"
    ditto "$BUILT" "$APP"
    # Through LaunchServices, not by running the binary: macOS only gives a
    # menu bar item to an app it launched itself. The price is that the app
    # isn't our child, so its output comes back through a log file.
    if open -g --stdout "$APP_LOG" --stderr "$APP_LOG" "$APP"; then
      echo "$(date +%H:%M:%S)  running ($((SECONDS - started))s build)"
    else
      echo "$(date +%H:%M:%S)  built, but macOS wouldn't launch it"
    fi
  else
    # Just the compiler's file:line errors, once each; the tail if there are none.
    grep -E "^error: /" "$BUILD_LOG" | sed 's/: FixIt(.*//' | awk '!seen[$0]++'
    grep -qE "^error: /" "$BUILD_LOG" || tail -15 "$BUILD_LOG"
    echo "$(date +%H:%M:%S)  build failed; the last good build keeps running"
  fi
}

echo "Menubar Dev: watching $ROOT (Ctrl-C to stop)"
# A copy left behind by an earlier run would make the new one quit on launch.
stop_app
if pgrep -f "$INSTALLED/Contents/MacOS/Menubar" >/dev/null; then
  INSTALLED_WAS_RUNNING=1
  echo "Quitting the installed Menubar until this stops"
  osascript -e 'tell application id "dev.fabio.menubar" to quit' >/dev/null 2>&1 \
    || pkill -f "$INSTALLED/Contents/MacOS/Menubar"
fi

# Anything the app prints (a crash, an NSLog) shows up here.
mkdir -p "$ROOT/build"
: >"$APP_LOG"
tail -n 0 -F "$APP_LOG" 2>/dev/null &
TAIL_PID=$!

last=""
while true; do
  current="$(fingerprint)"
  if [ "$current" != "$last" ]; then
    # Taken before the build, so edits that land while it runs trigger another.
    last="$current"
    rebuild
  fi
  sleep 1
done
