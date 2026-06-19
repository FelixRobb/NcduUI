#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_DIR="$ROOT/build/DerivedData"
PRODUCTS="$BUILD_DIR/Build/Products/Release"
APP="$PRODUCTS/NcduUI.app"

echo "Building unsigned Release NcduUI.app…"
xcodebuild \
  -project NcduUI.xcodeproj \
  -scheme NcduUI \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="-" \
  build

if [[ ! -d "$APP" ]]; then
  echo "error: expected app at $APP" >&2
  exit 1
fi

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
ZIP_NAME="NcduUI-${VERSION}-macOS-unsigned.zip"
OUT="$ROOT/build/$ZIP_NAME"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
ditto -c -k --keepParent "$APP" "$OUT"

echo "Created $OUT"
echo "Version: $VERSION"
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/NcduUI" | tr ' ' ', ')"
