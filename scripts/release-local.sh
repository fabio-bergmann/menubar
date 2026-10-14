#!/usr/bin/env bash
# Local release: build Menubar from a COMMITTED ref and install it to
# /Applications. There is no Apple Developer licence behind this app, so
# nothing is notarized. An app built on this machine carries no quarantine
# flag, though, so an ad-hoc signature is all macOS asks of it.
#
#   scripts/release-local.sh               # build main
#   scripts/release-local.sh origin/main   # what the in-app Update button runs
#
# The build runs from a `git archive` export in a temp dir, never from the
# working tree, so a parallel session's uncommitted work can't leak into the
# installed app.
set -euo pipefail

REF="${1:-main}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Menubar"
BUNDLE_ID="dev.fabio.menubar"
APP_DEST="/Applications/$APP_NAME.app"

FULL_SHA="$(git -C "$REPO_ROOT" rev-parse --verify "$REF^{commit}")" || {
  echo "error: unknown ref '$REF'" >&2
  exit 1
}
SHA="${FULL_SHA:0:7}"

BUILD_DIR="$(mktemp -d -t menubar-release)"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "==> Exporting $REF ($SHA) to $BUILD_DIR"
git -C "$REPO_ROOT" archive "$REF" | tar -x -C "$BUILD_DIR"

# The sha and the checkout's path ride into Info.plist so the installed app can
# compare itself with origin/main and rerun this script to update.
MENUBAR_BUILD_SHA="$FULL_SHA" MENUBAR_REPO_PATH="$REPO_ROOT" \
  bash "$BUILD_DIR/scripts/build-app.sh" "$BUILD_DIR/build"

APP_SRC="$BUILD_DIR/build/$APP_NAME.app"
[ -d "$APP_SRC" ] || { echo "error: build produced no app at $APP_SRC" >&2; exit 1; }

# The installed copy only: a build running from elsewhere is left alone.
INSTALLED_BIN="$APP_DEST/Contents/MacOS/Menubar"
app_running() { pgrep -f "$INSTALLED_BIN" >/dev/null; }
wait_for_exit() { for _ in $(seq 1 20); do app_running || return 0; sleep 0.25; done; return 1; }

if app_running; then
  echo "==> Quitting running $APP_NAME"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  if ! wait_for_exit; then
    # macOS can refuse the Apple event. The tiers are already on disk, and
    # macOS shows every icon again the moment the app is gone.
    pkill -f "$INSTALLED_BIN" || true
    wait_for_exit || { echo "error: $APP_NAME is still running. Quit it and re-run." >&2; exit 1; }
  fi
fi

echo "==> Installing to $APP_DEST"
rm -rf "$APP_DEST"
ditto "$APP_SRC" "$APP_DEST"

echo "==> Installed $APP_NAME ($REF @ $SHA)"
open "$APP_DEST"
