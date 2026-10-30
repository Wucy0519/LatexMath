#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macosx14.0"
BUILD="$ROOT/build"
APP="$ROOT/../公式台.app"
KATEX="$ROOT/node_modules/katex/dist"
TEMML="$ROOT/node_modules/temml/dist/temml.js"

cd "$ROOT"
node Tests/edit.test.mjs

killall "公式台" 2>/dev/null || true

rm -rf "$BUILD" "$APP"
mkdir -p "$BUILD/icon.iconset" \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Resources/vendor/katex/fonts" \
  "$APP/Contents/Resources/vendor/temml" \
  "$APP/Contents/Resources/fixtures"

swiftc -sdk "$SDK" -target "$TARGET" -O -framework AppKit \
  -o "$BUILD/MakeIcon" "$ROOT/Tools/MakeIcon.swift"
"$BUILD/MakeIcon" "$BUILD/icon-1024.png"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$BUILD/icon-1024.png" --out "$BUILD/icon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$BUILD/icon-1024.png" --out "$BUILD/icon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD/icon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

node "$ROOT/Tests/make-fixtures.mjs" "$APP/Contents/Resources/fixtures"

cp "$ROOT/Resources/index.html" \
  "$ROOT/Resources/app.css" \
  "$ROOT/Resources/app.js" \
  "$ROOT/Resources/edit.js" \
  "$ROOT/Resources/palette.js" \
  "$ROOT/Resources/examples.json" \
  "$ROOT/Resources/render.html" \
  "$APP/Contents/Resources/"
cp "$KATEX/katex.min.js" "$KATEX/katex.min.css" "$APP/Contents/Resources/vendor/katex/"
cp "$KATEX/fonts/"*.woff2 "$APP/Contents/Resources/vendor/katex/fonts/"
cp "$TEMML" "$APP/Contents/Resources/vendor/temml/temml.js"

swiftc -sdk "$SDK" -target "$TARGET" -O -whole-module-optimization \
  -framework AppKit -framework WebKit -framework UniformTypeIdentifiers \
  -o "$APP/Contents/MacOS/公式台" \
  "$ROOT/Sources/LibraryStore.swift" \
  "$ROOT/Sources/OfficeMath.swift" \
  "$ROOT/Sources/Clipboard.swift" \
  "$ROOT/Sources/Rasterizer.swift" \
  "$ROOT/Sources/SelfTest.swift" \
  "$ROOT/Sources/EditorController.swift" \
  "$ROOT/Sources/AppMain.swift"

cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/公式台" --self-test
echo "已生成 $APP"
