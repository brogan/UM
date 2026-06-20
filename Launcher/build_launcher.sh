#!/usr/bin/env bash
# Rebuilds UM Launcher.app from source.
# Run from any directory: bash Launcher/build_launcher.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
BUNDLE="$REPO_DIR/UM Launcher.app"

echo "=== Generating icon ==="
cd "$SCRIPT_DIR"
swiftc generate_icon.swift -o generate_icon
./generate_icon /tmp/um_iconset.iconset
iconutil -c icns /tmp/um_iconset.iconset -o /tmp/UMIcon.icns
rm generate_icon

echo "=== Compiling launcher ==="
swiftc UMLauncherMain.swift -o launch-um

echo "=== Assembling bundle ==="
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"
cp launch-um "$BUNDLE/Contents/MacOS/launch-um"
chmod +x "$BUNDLE/Contents/MacOS/launch-um"
cp /tmp/UMIcon.icns "$BUNDLE/Contents/Resources/UMIcon.icns"
cp UMLauncherMain.swift "$BUNDLE/Contents/Resources/UMLauncherMain.swift"
rm launch-um

echo "=== Done: $BUNDLE ==="
echo "Drag it to the Dock, or: open '$BUNDLE'"
