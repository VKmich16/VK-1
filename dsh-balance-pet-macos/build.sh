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
for sprite in sprite.png sprite-gpt.png sprite-claude.png sprite-gemini.png sprite-deepseek-offline.png \
              sprite-expression-nervous.png sprite-expression-aloof.png sprite-expression-calm.png; do
  cp "$ROOT/Resources/$sprite" "$APP/Contents/Resources/$sprite"
done
for patch in "$ROOT"/Resources/face-*.png; do
  cp "$patch" "$APP/Contents/Resources/"
done
for extra in hit.mp3 feed.mp3 pot_land.mp3 pot_off.mp3; do
  cp "$ROOT/Resources/$extra" "$APP/Contents/Resources/$extra"
done
for hand in 0 1 2 3 4; do
  cp "$ROOT/Resources/pat_hand_$hand.png" "$APP/Contents/Resources/pat_hand_$hand.png"
done
cp "$ROOT/Resources/rice.png" "$APP/Contents/Resources/rice.png"
cp "$ROOT/Resources/iron-bowl.png" "$APP/Contents/Resources/iron-bowl.png"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# Finder metadata (com.apple.FinderInfo) makes codesign refuse the bundle.
dot_clean -m "$APP" 2>/dev/null || true
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP" || {
  xattr -cr "$APP" 2>/dev/null || true
  codesign --force --sign - "$APP"
}
codesign --verify --strict "$APP"

# Keep the last successful build usable until the replacement is ready.
if [[ -e "$FINAL" ]]; then mv "$FINAL" "$STAGING/previous.app"; fi
if ! mv "$APP" "$FINAL"; then
  if [[ -d "$STAGING/previous.app" ]]; then mv "$STAGING/previous.app" "$FINAL"; fi
  exit 1
fi
echo "built: $FINAL"
du -sh "$FINAL"
