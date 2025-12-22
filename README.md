<img src="docs/icon.png" width="128" height="128" alt="MyShot Icon">

# MyShot

**A free, open-source screenshot tool for macOS** - inspired by CleanShot X.

[![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## ✨ Features

- 📸 **Screenshot Capture** - Area, Fullscreen, Window selection
- 🎬 **Screen Recording** - Record video or GIF
- 📝 **OCR** - Extract text from screenshots
- 🎨 **Custom Wallpaper** - Add beautiful gradient backgrounds
- 📋 **Quick Access Overlay** - Copy, Save with one click
- 📂 **Capture History** - Browse past captures
- ⌨️ **Global Hotkeys** - Ctrl+Shift+3/4/5/6

## 📥 Installation

### Download DMG
1. Download the latest release from [Releases](https://github.com/datntpro/myshot/releases)
2. Open the DMG and drag MyShot to Applications
3. Right-click and Open (first time only)
4. Grant required permissions when prompted

### Build from Source
```bash
git clone https://github.com/datntpro/myshot.git
cd myshot
./build.sh
```

## 🎮 Usage

### Keyboard Shortcuts
| Shortcut       | Action             |
| -------------- | ------------------ |
| `Ctrl+Shift+3` | Capture Fullscreen |
| `Ctrl+Shift+4` | Capture Area       |
| `Ctrl+Shift+5` | Capture Window     |
| `Ctrl+Shift+6` | Capture Text (OCR) |

### Menu Bar
Click the camera icon in the menu bar to access all features.

## ⚙️ Permissions Required

MyShot requires the following permissions:

1. **Screen Recording** - To capture screenshots and record screen
2. **Accessibility** - For global keyboard shortcuts

Go to **System Settings → Privacy & Security** to grant permissions.

## 🛠️ Tech Stack

- Swift 5.9 / SwiftUI
- ScreenCaptureKit
- AVFoundation
- Vision (OCR)

## 📄 License

MIT License - feel free to use and modify!

## 🙏 Credits

Inspired by [CleanShot X](https://cleanshot.com) - but free and open source!

---

Made with ❤️ by [@datntpro](https://github.com/datntpro)
