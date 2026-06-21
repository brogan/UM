#!/usr/bin/env bash
# Rebuilds UM Launcher.app from source.
# Run from any directory: bash Launcher/build_launcher.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
BUNDLE="$REPO_DIR/UM Launcher.app"
ICONSET="$(mktemp -d /tmp/um_iconset.XXXXXX)/UMIcon.iconset"
ICONFILE="$(mktemp /tmp/UMIcon.XXXXXX).icns"

echo "=== Generating icon ==="
cd "$SCRIPT_DIR"
swiftc generate_icon.swift -o generate_icon
./generate_icon "$ICONSET"
if ! iconutil -c icns "$ICONSET" -o "$ICONFILE"; then
  if [[ -f "$BUNDLE/Contents/Resources/UMIcon.icns" ]]; then
    echo "iconutil rejected generated iconset; keeping existing app icon."
    ICONFILE="$BUNDLE/Contents/Resources/UMIcon.icns"
  else
    exit 1
  fi
fi
rm generate_icon

echo "=== Compiling launcher ==="
swiftc UMLauncherMain.swift -o launch-um

echo "=== Assembling bundle ==="
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"
cp launch-um "$BUNDLE/Contents/MacOS/launch-um"
chmod +x "$BUNDLE/Contents/MacOS/launch-um"
if [[ "$ICONFILE" != "$BUNDLE/Contents/Resources/UMIcon.icns" ]]; then
  cp "$ICONFILE" "$BUNDLE/Contents/Resources/UMIcon.icns"
fi
cp UMLauncherMain.swift "$BUNDLE/Contents/Resources/UMLauncherMain.swift"
rm launch-um

echo "=== Done: $BUNDLE ==="
echo "Drag it to the Dock, or: open '$BUNDLE'"
