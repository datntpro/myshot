#!/bin/bash

# MyShot Build Script
# Builds the app for release and creates a DMG

set -e

APP_NAME="MyShot"
BUILD_DIR="$(pwd)/.build/release"
OUTPUT_DIR="$(pwd)/dist"
DMG_NAME="$APP_NAME.dmg"

echo "🔨 Building $APP_NAME for release..."

# Build for release
swift build -c release

echo "📦 Creating app bundle..."

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create app bundle structure
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
cp Sources/Info.plist "$APP_BUNDLE/Contents/"

# Copy app icon
if [ -f "Sources/Resources/AppIcon.icns" ]; then
    cp Sources/Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
    echo "✅ App icon included"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc code signing (required for running on macOS)
echo "🔐 Code signing..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "✅ App bundle created at: $APP_BUNDLE"

# Create DMG
echo "💿 Creating DMG..."

# Remove old DMG if exists
rm -f "$OUTPUT_DIR/$DMG_NAME"

# Create temporary DMG folder
DMG_TEMP="$OUTPUT_DIR/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to temp folder
cp -r "$APP_BUNDLE" "$DMG_TEMP/"

# Create symbolic link to Applications
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP" -ov -format UDZO "$OUTPUT_DIR/$DMG_NAME"

# Cleanup
rm -rf "$DMG_TEMP"

echo ""
echo "🎉 Build complete!"
echo "📁 App: $APP_BUNDLE"
echo "💿 DMG: $OUTPUT_DIR/$DMG_NAME"
echo ""
echo "To install:"
echo "1. Open the DMG and drag MyShot to Applications"
echo "2. Run the app - grant Accessibility & Screen Recording permissions when prompted"
echo "3. Use Ctrl+Shift+3/4/5/6 for shortcuts or click the menu bar icon"
