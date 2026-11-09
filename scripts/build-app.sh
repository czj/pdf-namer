#!/bin/zsh
# Build "PDF Namer.app" (release), sign it ad hoc and install it in ~/Applications.
# Also installs the CLI as ~/.local/bin/pdf-namer.
#   scripts/build-app.sh [--no-install]
set -euo pipefail
cd "${0:A:h}/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build -c release --product PDFNamerApp
swift build -c release --product pdf-namer
BIN=$(swift build -c release --show-bin-path)

APP="build/PDF Namer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/PDFNamerApp" "$APP/Contents/MacOS/PDFNamerApp"
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
