#!/usr/bin/env bash
# Single kill + build + run entrypoint for AutoNovel Studio (SwiftPM GUI).
# Canonical contract: build-run-debug references/run-button-bootstrap.md

set -euo pipefail

MODE="${1:-run}"
APP_NAME="AutoNovelStudio"
BUNDLE_ID="org.nousresearch.autonovelstudio"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--build-only]" >&2
}

case "$MODE" in
  run|--run|"")
    MODE="run"
    ;;
  --debug|debug)
    MODE="debug"
    ;;
  --logs|logs)
    MODE="logs"
    ;;
  --telemetry|telemetry)
    MODE="telemetry"
    ;;
  --verify|verify)
    MODE="verify"
    ;;
  --build-only|build-only)
    MODE="build-only"
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

ICON_MASTER="$DIST_DIR/AppIcon-1024.png"
ICONSET="$DIST_DIR/AppIcon.iconset"
/usr/bin/python3 "$ROOT_DIR/script/render_app_icon.py" "$ICON_MASTER"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
/usr/bin/sips -z 16 16 "$ICON_MASTER" --out "$ICONSET/icon_16x16.png" >/dev/null
/usr/bin/sips -z 32 32 "$ICON_MASTER" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
/usr/bin/sips -z 32 32 "$ICON_MASTER" --out "$ICONSET/icon_32x32.png" >/dev/null
/usr/bin/sips -z 64 64 "$ICON_MASTER" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
/usr/bin/sips -z 128 128 "$ICON_MASTER" --out "$ICONSET/icon_128x128.png" >/dev/null
/usr/bin/sips -z 256 256 "$ICON_MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
/usr/bin/sips -z 256 256 "$ICON_MASTER" --out "$ICONSET/icon_256x256.png" >/dev/null
/usr/bin/sips -z 512 512 "$ICON_MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
/usr/bin/sips -z 512 512 "$ICON_MASTER" --out "$ICONSET/icon_512x512.png" >/dev/null
/usr/bin/sips -z 1024 1024 "$ICON_MASTER" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
/usr/bin/iconutil -c icns -o "$APP_RESOURCES/AppIcon.icns" "$ICONSET"
rm -rf "$APP_RESOURCES/AutoNovelStudio.help"
cp -R "$ROOT_DIR/Sources/AutoNovelStudio/Resources/AutoNovelStudio.help" \
  "$APP_RESOURCES/AutoNovelStudio.help"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleHelpBookFolder</key>
  <string>AutoNovelStudio.help</string>
  <key>CFBundleHelpBookName</key>
  <string>AutoNovel Studio Help</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>AutoNovel Studio</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
  </dict>
</dict>
</plist>
PLIST

# Local development signing only (ad-hoc / identity "-").
# Not distribution: no Developer ID, no hardened runtime, no notarization,
# and no invented entitlements plist. Gatekeeper (`spctl -a`) will reject
# this signature by design; that is not a local launch failure.
sign_app_bundle_ad_hoc() {
  /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
}

# Report signing class for triage (codesign integrity ≠ Gatekeeper trust).
report_local_signing_state() {
  local codesign_dv
  codesign_dv="$(/usr/bin/codesign -dv "$APP_BUNDLE" 2>&1)"
  if printf '%s\n' "$codesign_dv" | /usr/bin/grep -Eq 'Signature=adhoc|flags=0x2\(adhoc\)'; then
    echo "Signing: ad-hoc (local development; Gatekeeper/spctl reject is expected)"
  else
    echo "Signing: unexpected non-adhoc state — inspect with:" >&2
    echo "  codesign -dvvv --entitlements - \"$APP_BUNDLE\"" >&2
    echo "  codesign --verify --deep --strict \"$APP_BUNDLE\"" >&2
    return 1
  fi
}

sign_app_bundle_ad_hoc

open_app() {
  export AUTONOVEL_PROJECT_DIR="$ROOT_DIR"
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    echo "Launched $APP_BUNDLE"
    ;;
  debug)
    export AUTONOVEL_PROJECT_DIR="$ROOT_DIR"
    lldb -- "$APP_BINARY"
    ;;
  logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  verify)
    report_local_signing_state
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "Verified $APP_NAME is running from $APP_BUNDLE"
    ;;
  build-only)
    report_local_signing_state
    echo "Built $APP_BUNDLE"
    ;;
  *)
    usage
    exit 2
    ;;
esac
