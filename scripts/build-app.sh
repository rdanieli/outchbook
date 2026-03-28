#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/OuchBook.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building OuchBook release binary..."
swift build -c release --product OuchBookMenuBar

echo "Assembling app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BUILD_DIR/OuchBookMenuBar" "$MACOS_DIR/OuchBook"
cp -R "$BUILD_DIR/OuchBook_OuchBook.bundle" "$RESOURCES_DIR/OuchBook_OuchBook.bundle"

chmod +x "$MACOS_DIR/OuchBook"

if command -v codesign >/dev/null 2>&1; then
  echo "Applying ad-hoc code signature..."
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "Built app bundle at: $APP_DIR"
