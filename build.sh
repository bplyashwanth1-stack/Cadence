#!/bin/zsh
# Builds Cadence.app and installs it to ~/Applications.
set -e
cd "$(dirname "$0")"
APP=build/Cadence.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp Info.plist "$APP/Contents/"
cp Fonts/*.ttf "$APP/Contents/Resources/Fonts/" 2>/dev/null || true
# Builds for this Mac's chip (arm64 or x86_64). The GitHub release is universal; see .github/workflows/release.yml.
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.0" Sources/*.swift -o "$APP/Contents/MacOS/Cadence"
# A stable local identity keeps macOS permissions across rebuilds (see scripts/signing-identity.sh).
IDENTITY=$(scripts/signing-identity.sh 2>/dev/null || true)
codesign --force --sign "${IDENTITY:--}" "$APP"
mkdir -p ~/Applications
rm -rf ~/Applications/Cadence.app
cp -R "$APP" ~/Applications/
echo "Installed to ~/Applications/Cadence.app"
