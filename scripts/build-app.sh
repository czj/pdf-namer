#!/bin/zsh
# Build "PDF Namer.app" (release), sign it ad hoc and install it in ~/Applications.
# Also installs the CLI as ~/.local/bin/pdf-namer.
#   scripts/build-app.sh [--no-install]
set -euo pipefail
ROOT="${0:A:h:h}"  # absolute: actool resolves relative paths against $PWD, not the cwd
cd "$ROOT"

swift build -c release --product PDFNamerApp
swift build -c release --product pdf-namer
BIN=$(swift build -c release --show-bin-path)

APP="$ROOT/build/PDF Namer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/PDFNamerApp" "$APP/Contents/MacOS/PDFNamerApp"
# Icon Composer icon (Liquid Glass layers) → Assets.car + AppIcon.icns
if ! xcrun actool "$ROOT/Resources/AppIcon.icon" --compile "$APP/Contents/Resources" --platform macosx \
     --minimum-deployment-target 27.0 --app-icon AppIcon \
     --output-partial-info-plist "$ROOT/build/icon-partial.plist" > "$ROOT/build/actool.log"; then
  echo "✗ actool : voir build/actool.log" >&2
  exit 1
fi
codesign --force --sign - --timestamp=none "$APP"
echo "✓ $APP"

if [[ "${1:-}" != "--no-install" ]]; then
  mkdir -p ~/Applications ~/.local/bin
  pkill -x PDFNamerApp 2>/dev/null || true
  rm -rf ~/Applications/"PDF Namer.app"
  cp -R "$APP" ~/Applications/
  cp "$BIN/pdf-namer" ~/.local/bin/pdf-namer
  echo "✓ installé : ~/Applications/PDF Namer.app et ~/.local/bin/pdf-namer"
fi
