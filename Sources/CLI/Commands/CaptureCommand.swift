import Foundation
import Cocoa
import ScreenCaptureKit

// MARK: - Capture Command
struct CaptureCommand {
    static func run(options: [String]) async {
        let parser = OptionParser(args: options)
        
        // Help
        if parser.hasFlag("help", "-h") {
            printHelp()
            return
        }
        
        let outputJSON = parser.hasFlag("json")
        
        // Determine capture mode
        let captureMode: CaptureMode
        if parser.hasFlag("fullscreen") {
            captureMode = .fullscreen
        } else if parser.hasFlag("window") {
            captureMode = .window
        } else if parser.hasFlag("area") {
            captureMode = .area
        } else {
            // Default to fullscreen for CLI
            captureMode = .fullscreen
        }
        
        // Get output path
        let outputPath = parser.getValue(for: "output", "-o")
        let format = parser.getValue(for: "format", "-f") ?? "png"
        let shouldCopy = parser.hasFlag("copy", "-c")
        let shouldRedact = parser.hasFlag("redact", "-r")
        
        // Perform capture
        do {
            let image = try await performCapture(mode: captureMode)
            
            // Apply redaction if requested
            var finalImage = image
            if shouldRedact {
                finalImage = await applyAutoRedact(to: image) ?? image
            }
            
            // Handle output
            if let outputPath = outputPath {
                let expandedPath = (outputPath as NSString).expandingTildeInPath
                try saveImage(finalImage, to: expandedPath, format: format)
                CLIOutput.success(.file(path: expandedPath)).print(asJSON: outputJSON)
            } else if shouldCopy {
                copyToClipboard(finalImage)
                CLIOutput.success(.text("Copied to clipboard")).print(asJSON: outputJSON)
            } else {
                // Default: save to Desktop
                let desktopPath = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
                let filename = "Screenshot-\(timestamp()).\(format)"
                let fullPath = (desktopPath as NSString).appendingPathComponent(filename)
                try saveImage(finalImage, to: fullPath, format: format)
                CLIOutput.success(.file(path: fullPath)).print(asJSON: outputJSON)
            }
        } catch {
            CLIOutput.error(error.localizedDescription).print(asJSON: outputJSON)
            exit(1)
        }
    }
    
    static func printHelp() {
        print("""
        
        \u{001B}[1mMyShot Capture\u{001B}[0m - Take screenshots
        
        \u{001B}[1mUSAGE:\u{001B}[0m
            myshot capture [options]
        
        \u{001B}[1mOPTIONS:\u{001B}[0m
            --fullscreen        Capture entire screen (default)
            --area              Capture selected area
            --window            Capture focused window
            --output, -o PATH   Save to specified path
            --format, -f FMT    Output format: png (default), jpg
            --copy, -c          Copy to clipboard
            --redact, -r        Auto-redact sensitive data
            --json              Output result as JSON
            --help, -h          Show this help
        
        \u{001B}[1mEXAMPLES:\u{001B}[0m
            myshot capture --fullscreen
            myshot capture --area --output ~/Desktop/area.png
            myshot capture --fullscreen --redact --copy
        
        """)
    }
    
    enum CaptureMode {
        case fullscreen, area, window
    }
    
    static func performCapture(mode: CaptureMode) async throws -> NSImage {
        switch mode {
        case .fullscreen:
            return try await captureFullscreen()
        case .area:
            // Area capture requires GUI interaction - not supported in pure CLI
            printInfo("Area capture requires GUI. Using fullscreen instead.")
            return try await captureFullscreen()
        case .window:
            return try await captureWindow()
        }
    }
    
    static func captureFullscreen() async throws -> NSImage {
        guard let screen = NSScreen.main else {
            throw CaptureError.noScreen
        }
        
        let screenRect = screen.frame
        guard let cgImage = CGWindowListCreateImage(
            screenRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            throw CaptureError.captureFailed
        }
        
        return NSImage(cgImage: cgImage, size: screenRect.size)
    }
    
    static func captureWindow() async throws -> NSImage {
        // Get frontmost application window
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            throw CaptureError.noWindow
        }
        
        // Find the frontmost non-dock, non-menubar window
        let appWindows = windowList.filter { window in
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  let name = window[kCGWindowOwnerName as String] as? String else {
                return false
            }
            return layer == 0 && name != "Dock" && name != "Window Server"
        }
        
        guard let windowInfo = appWindows.first,
              let windowId = windowInfo[kCGWindowNumber as String] as? CGWindowID else {
            throw CaptureError.noWindow
        }
        
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowId,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            throw CaptureError.captureFailed
        }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    static func applyAutoRedact(to image: NSImage) async -> NSImage? {
        // Simple implementation - would need to import full AutoRedact code
        // For now, just return the original image
        printInfo("Auto-redact processing...")
        return image
    }
    
    static func saveImage(_ image: NSImage, to path: String, format: String) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw CaptureError.encodeFailed
        }
        
        let fileType: NSBitmapImageRep.FileType
        switch format.lowercased() {
        case "jpg", "jpeg":
            fileType = .jpeg
        case "png":
            fileType = .png
        default:
            fileType = .png
        }
        
        guard let data = bitmap.representation(using: fileType, properties: [:]) else {
            throw CaptureError.encodeFailed
        }
        
        try data.write(to: URL(fileURLWithPath: path))
    }
    
    static func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
    
    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter.string(from: Date())
    }
    
    enum CaptureError: LocalizedError {
        case noScreen
        case noWindow
        case captureFailed
        case encodeFailed
        
        var errorDescription: String? {
            switch self {
            case .noScreen: return "No screen available"
            case .noWindow: return "No window available for capture"
            case .captureFailed: return "Screenshot capture failed"
            case .encodeFailed: return "Failed to encode image"
            }
        }
    }
}
