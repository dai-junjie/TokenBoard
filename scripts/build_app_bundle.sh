#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="LabforgeMenuBarApp"
DISPLAY_NAME="TokenBoard"
INFO_PLIST="$ROOT_DIR/Packaging/Info.plist"
SCRATCH_DIR="$ROOT_DIR/.build/app"
PACKAGE_DIR="$ROOT_DIR/.build/package"
APP_DIR="$PACKAGE_DIR/$DISPLAY_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RELEASE_BIN="$SCRATCH_DIR/release/$APP_NAME"
APP_ICON="$ROOT_DIR/Packaging/AppIcon.icns"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

swift build \
  -c release \
  --product "$APP_NAME" \
  --package-path "$ROOT_DIR" \
  --scratch-path "$SCRATCH_DIR" >&2

cp "$RELEASE_BIN" "$MACOS_DIR/$APP_NAME"
cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"
cp "$APP_ICON" "$RESOURCES_DIR/AppIcon.icns"
chmod +x "$MACOS_DIR/$APP_NAME"

codesign --force --deep --sign - "$APP_DIR" >&2

echo "$APP_DIR"
