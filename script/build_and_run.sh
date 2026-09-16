#!/bin/bash

set -euo pipefail

MODE="${1:---run}"
APP_NAME="AutoNovelStudio"
BUNDLE_ID="org.nousresearch.autonovelstudio"
MIN_OS="14.0"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

show_logs() {
  /usr/bin/log show --last 8m --style compact \
    --predicate "process == '$APP_NAME' OR eventMessage CONTAINS[c] '$APP_NAME'" || true
}

show_telemetry() {
  /usr/bin/log stream --style compact \
    --predicate "process == '$APP_NAME' OR eventMessage CONTAINS[c] '$APP_NAME'"
}

if [[ "$MODE" == "--logs" ]]; then
  show_logs
  exit 0
fi

if [[ "$MODE" == "--telemetry" ]]; then
  show_telemetry
  exit 0
fi

cd "$ROOT_DIR"
swift build

if [[ "$MODE" == "--verify" ]]; then
  swift test
fi

if [[ "$MODE" == "--debug" ]]; then
  lldb "$ROOT_DIR/.build/debug/$APP_NAME"
  exit 0
fi

/usr/bin/pkill -x "$APP_NAME" 2>/dev/null || true
/bin/rm -rf "$APP_BUNDLE"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
/bin/mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
/bin/cp "$ROOT_DIR/.build/debug/$APP_NAME" "$MACOS_DIR/$APP_NAME"

ICON_MASTER="$DIST_DIR/AppIcon-1024.png"
ICONSET="$DIST_DIR/AppIcon.iconset"
/usr/bin/python3 "$ROOT_DIR/script/render_app_icon.py" "$ICON_MASTER"
/bin/rm -rf "$ICONSET"
/bin/mkdir -p "$ICONSET"
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
/usr/bin/iconutil -c icns -o "$RESOURCES_DIR/AppIcon.icns" "$ICONSET"
/bin/rm -rf "$RESOURCES_DIR/AutoNovelStudio.help"
/bin/cp -R "$ROOT_DIR/Sources/AutoNovelStudio/Resources/AutoNovelStudio.help" "$RESOURCES_DIR/AutoNovelStudio.help"

/bin/cat > "$CONTENTS_DIR/Info.plist" <<PLIST
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
  <string>$MIN_OS</string>
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

/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

if [[ "$MODE" == "--build-only" ]]; then
  echo "Built $APP_BUNDLE"
  exit 0
fi

export AUTONOVEL_PROJECT_DIR="$ROOT_DIR"
/usr/bin/open -n "$APP_BUNDLE"
if [[ "$MODE" == "--verify" ]]; then
  /bin/sleep 2
  /usr/bin/pgrep -x "$APP_NAME" >/dev/null
  echo "Verified $APP_NAME is running from $APP_BUNDLE"
else
  echo "Launched $APP_BUNDLE"
fi
