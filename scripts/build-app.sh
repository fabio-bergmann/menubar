#!/usr/bin/env bash
# Builds "Menubar.app" from the tree this script lives in. It only builds:
# nothing is installed or launched (that's scripts/release-local.sh).
#
#   scripts/build-app.sh            # -> build/Menubar.app
#   scripts/build-app.sh /some/dir  # -> /some/dir/Menubar.app
#
# MENUBAR_VARIANT=dev builds "Menubar Dev.app" instead: a debug build
# with its own bundle id, so it keeps separate settings and can run beside the
# installed app (that's scripts/dev.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build}"
if [ "${MENUBAR_VARIANT:-}" = dev ]; then
  CONFIG=debug
  APP_NAME="Menubar Dev"
  BUNDLE_ID="dev.fabio.menubar.dev"
else
  CONFIG=release
  APP_NAME="Menubar"
  BUNDLE_ID="dev.fabio.menubar"
fi
APP="$OUT/$APP_NAME.app"

echo "==> Compiling"
swift build -c "$CONFIG" --package-path "$ROOT" --product Menubar
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/Menubar"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Menubar"

# The icon is drawn by the app itself, so there's no binary asset to keep in git.
ICON_DIR="$(mktemp -d -t menubar-icon)"
trap 'rm -rf "$ICON_DIR"' EXIT
"$BIN" --render-icon "$ICON_DIR/AppIcon.iconset"
iconutil -c icns "$ICON_DIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

# The in-app Update button compares this commit with origin/main and reruns
# release-local.sh from this checkout. Both are empty for a plain local build,
# which switches the button off.
PLIST="$APP/Contents/Info.plist"
cp "$ROOT/Support/Info.plist" "$PLIST"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
plutil -replace CFBundleName -string "$APP_NAME" "$PLIST"
plutil -replace CFBundleDisplayName -string "$APP_NAME" "$PLIST"
plutil -insert MBBuildSHA -string "${MENUBAR_BUILD_SHA:-}" "$PLIST"
plutil -insert MBRepoPath -string "${MENUBAR_REPO_PATH:-}" "$PLIST"

# Signed with the self-signed certificate from scripts/make-signing-cert.sh,
# so the signature names the certificate rather than this build and macOS
# keeps the Accessibility grant across builds. Without it, an ad-hoc
# signature still runs here (the app never leaves this Mac) but loses the
# grant every build.
IDENTITY="Fabio Local Code Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "warning: no \"$IDENTITY\" certificate; signing ad hoc, so Accessibility won't survive this build." >&2
  echo "         Run scripts/make-signing-cert.sh once to fix that." >&2
  codesign --force --sign - "$APP"
fi

echo "==> Built $APP"
