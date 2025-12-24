#!/bin/bash
# MyShot CLI Installation Script
# Creates symlink to /usr/local/bin/myshot

set -e

CLI_NAME="myshot"
INSTALL_DIR="/usr/local/bin"
APP_PATH="/Applications/MyShot.app"
CLI_BINARY="${APP_PATH}/Contents/MacOS/myshot-cli"

echo "🚀 MyShot CLI Installer"
echo ""

# Check if MyShot.app exists
if [ ! -d "$APP_PATH" ]; then
    # Try to find in build directory
    BUILD_CLI=".build/release/myshot-cli"
    if [ -f "$BUILD_CLI" ]; then
        CLI_BINARY="$(pwd)/$BUILD_CLI"
        echo "📍 Using development build: $CLI_BINARY"
    else
        echo "❌ Error: MyShot.app not found in /Applications"
        echo "   Please install MyShot.app first, or build from source:"
        echo "   swift build -c release"
        exit 1
    fi
fi

# Check if CLI binary exists
if [ ! -f "$CLI_BINARY" ]; then
    echo "❌ Error: CLI binary not found at $CLI_BINARY"
    exit 1
fi

# Create /usr/local/bin if it doesn't exist
if [ ! -d "$INSTALL_DIR" ]; then
    echo "📁 Creating $INSTALL_DIR..."
    sudo mkdir -p "$INSTALL_DIR"
fi

# Remove existing symlink
if [ -L "$INSTALL_DIR/$CLI_NAME" ]; then
    echo "🔄 Removing existing symlink..."
    sudo rm "$INSTALL_DIR/$CLI_NAME"
fi

# Create symlink
echo "🔗 Creating symlink: $INSTALL_DIR/$CLI_NAME -> $CLI_BINARY"
sudo ln -sf "$CLI_BINARY" "$INSTALL_DIR/$CLI_NAME"

# Verify installation
if command -v myshot &> /dev/null; then
    echo ""
    echo "✅ MyShot CLI installed successfully!"
    echo ""
    echo "Usage:"
    echo "  myshot --help"
    echo "  myshot capture --fullscreen"
    echo "  myshot ocr ~/image.png"
    echo ""
else
    echo ""
    echo "⚠️  Installation completed, but 'myshot' command not found."
    echo "    You may need to add $INSTALL_DIR to your PATH:"
    echo "    export PATH=\"\$PATH:$INSTALL_DIR\""
fi
