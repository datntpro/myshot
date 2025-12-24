#!/bin/bash

# MyShot Build Script
# Builds the app for release and creates a beautiful DMG

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

# Create temporary read-write DMG  
TEMP_DMG="$OUTPUT_DIR/temp_$DMG_NAME"
rm -f "$TEMP_DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP" -ov -format UDRW "$TEMP_DMG"

# Mount and configure
echo "🎨 Configuring DMG appearance..."
DEVICE=$(hdiutil attach -readwrite -noverify "$TEMP_DMG" | egrep '^/dev/' | sed 1q | awk '{print $1}')
MOUNT_POINT="/Volumes/$APP_NAME"

sleep 2

# Set Finder view options using osascript
osascript <<EOF
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 800, 520}
        
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        
        -- Position icons nicely
        set position of item "$APP_NAME.app" of container window to {150, 200}
        set position of item "Applications" of container window to {450, 200}
        
        update without registering applications
        close
    end tell
end tell
EOF

# Wait for Finder
sleep 2

# Unmount
sync
hdiutil detach "$DEVICE" -quiet 2>/dev/null || hdiutil detach "$DEVICE" -force

# Convert to compressed read-only DMG
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DIR/$DMG_NAME"

# Cleanup
rm -f "$TEMP_DMG"
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
