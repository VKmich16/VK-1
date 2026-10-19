#!/bin/bash
# Build using only the macOS SDK and Xcode command line tools.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
NAME="DSHBalancePet"
SWIFTC="$(xcrun --find swiftc)"
LIPO="$(xcrun --find lipo)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64|x86_64|universal) ;;
  *) echo "Unsupported ARCH: $ARCH (use arm64, x86_64 or universal)" >&2; exit 1 ;;
esac

mkdir -p "$BUILD/ModuleCache" "$DIST"
STAGING="$(mktemp -d "$BUILD/bundle.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/DSH大肥鱼桌宠.app"
FINAL="$DIST/DSH大肥鱼桌宠.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

compile() {
  echo "==> compiling $1"
  "$SWIFTC" -swift-version 5 -O \
    -sdk "$SDK" \
    -module-cache-path "$BUILD/ModuleCache" \
    -target "$1-apple-macos13.0" \
    -o "$2" "$ROOT"/Sources/*.swift \
    -framework AppKit -framework Foundation
}

if [[ "$ARCH" == universal ]]; then
  compile arm64 "$STAGING/arm64"
  compile x86_64 "$STAGING/x86_64"
  "$LIPO" -create "$STAGING/arm64" "$STAGING/x86_64" -output "$APP/Contents/MacOS/$NAME"
else
  compile "$ARCH" "$APP/Contents/MacOS/$NAME"
fi

echo "==> copying four characters and original sound"
for sprite in sprite.png sprite-gpt.png sprite-claude.png sprite-gemini.png sprite-deepseek-offline.png; do
  cp "$ROOT/Resources/$sprite" "$APP/Contents/Resources/$sprite"
done
cp "$ROOT/Resources/hit.mp3" "$APP/Contents/Resources/hit.mp3"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

# Keep the last successful build usable until the replacement is ready.
if [[ -e "$FINAL" ]]; then mv "$FINAL" "$STAGING/previous.app"; fi
if ! mv "$APP" "$FINAL"; then
  if [[ -d "$STAGING/previous.app" ]]; then mv "$STAGING/previous.app" "$FINAL"; fi
  exit 1
fi
echo "built: $FINAL"
du -sh "$FINAL"
