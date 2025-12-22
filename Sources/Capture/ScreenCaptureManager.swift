import Cocoa

class ScreenCaptureManager: NSObject {
    static let shared = ScreenCaptureManager()
    
    private var selectionWindow: SelectionWindow?
    private var completionHandler: ((NSImage?) -> Void)?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Area Selection Capture
    func startAreaSelection(completion: @escaping (NSImage?) -> Void) {
        self.completionHandler = completion
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let window = SelectionWindow()
            self.selectionWindow = window
            
            window.onSelectionComplete = { [weak self] rect in
                self?.captureArea(rect: rect)
            }
            window.onCancel = { [weak self] in
                self?.completionHandler?(nil)
                self?.selectionWindow = nil
            }
            window.show()
        }
    }
    
    private func captureArea(rect: CGRect) {
        selectionWindow?.orderOut(nil)
        selectionWindow = nil
        
        // Small delay to let the selection window disappear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.captureRect(rect)
        }
    }
    
    private func captureRect(_ rect: CGRect) {
        guard let screen = NSScreen.main else {
            completionHandler?(nil)
            return
        }
        
        let screenHeight = screen.frame.height
        let flippedRect = CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        
        guard let cgImage = CGWindowListCreateImage(
            flippedRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            completionHandler?(nil)
            return
        }
        
        var image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        // Apply custom wallpaper if enabled
        if SettingsManager.shared.useCustomWallpaper {
            image = applyWallpaper(to: image)
        }
        
        completionHandler?(image)
    }
    
    private func applyWallpaper(to image: NSImage) -> NSImage {
        let settings = SettingsManager.shared
        let padding = CGFloat(settings.wallpaperPadding)
        let cornerRadius = CGFloat(settings.windowCornerRadius)
        
        let newSize = NSSize(
            width: image.size.width + padding * 2,
            height: image.size.height + padding * 2
        )
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        
        let bgRect = NSRect(origin: .zero, size: newSize)
        
        // Draw background based on type
        switch settings.wallpaperType {
        case "gradient":
            drawGradientBackground(in: bgRect, color1: settings.wallpaperColor, color2: settings.wallpaperColor2)
        case "image":
            if !settings.wallpaperImagePath.isEmpty, let bgImage = NSImage(contentsOfFile: settings.wallpaperImagePath) {
                bgImage.draw(in: bgRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            } else {
                settings.wallpaperColor?.setFill()
                bgRect.fill()
            }
        default: // solid
            settings.wallpaperColor?.setFill()
            bgRect.fill()
        }
        
        // Draw rounded image
        let imageRect = NSRect(
            x: padding,
            y: padding,
            width: image.size.width,
            height: image.size.height
        )
        
        NSGraphicsContext.saveGraphicsState()
        let clipPath = NSBezierPath(roundedRect: imageRect, xRadius: cornerRadius, yRadius: cornerRadius)
        clipPath.addClip()
        image.draw(in: imageRect)
        NSGraphicsContext.restoreGraphicsState()
        
        newImage.unlockFocus()
        
        return newImage
    }
    
    private func drawGradientBackground(in rect: NSRect, color1: NSColor?, color2: NSColor?) {
        let c1 = color1 ?? NSColor.purple
        let c2 = color2 ?? NSColor.blue
        
        let gradient = NSGradient(starting: c1, ending: c2)
        gradient?.draw(in: rect, angle: -45)
    }
    
    // MARK: - Fullscreen Capture
    func captureFullscreen(completion: @escaping (NSImage?) -> Void) {
        guard let screen = NSScreen.main else {
            completion(nil)
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let cgImage = CGWindowListCreateImage(
                screen.frame,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
            ) else {
                completion(nil)
                return
            }
            
            let image = NSImage(cgImage: cgImage, size: screen.frame.size)
            completion(image)
        }
    }
    
    // MARK: - Window Capture
    func captureWindow(completion: @escaping (NSImage?) -> Void) {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            completion(nil)
            return
        }
        
        let appWindows = windowList.filter { window in
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  let ownerName = window[kCGWindowOwnerName as String] as? String else {
                return false
            }
            return layer == 0 && ownerName != "Window Server" && ownerName != "Dock"
        }
        
        guard !appWindows.isEmpty else {
            completion(nil)
            return
        }
        
        // For simplicity, capture the first window
        if let windowId = appWindows.first?[kCGWindowNumber as String] as? CGWindowID {
            captureWindowById(windowId, completion: completion)
        } else {
            completion(nil)
        }
    }
    
    private func captureWindowById(_ windowId: CGWindowID, completion: @escaping (NSImage?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowId,
                [.bestResolution, .boundsIgnoreFraming]
            ) else {
                completion(nil)
                return
            }
            
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            completion(image)
        }
    }
}

// MARK: - Selection Window
class SelectionWindow: NSWindow {
    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    
    private var selectionView: SelectionView?
    
    init() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        
        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        
        let view = SelectionView(frame: frame)
        self.selectionView = view
        
        view.onSelectionComplete = { [weak self] rect in
            self?.onSelectionComplete?(rect)
        }
        view.onCancel = { [weak self] in
            self?.onCancel?()
        }
        
        self.contentView = view
    }
    
    func show() {
        self.makeKeyAndOrderFront(nil)
        if let view = selectionView {
            self.makeFirstResponder(view)
        }
    }
}

// MARK: - Selection View
class SelectionView: NSView {
    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var isSelecting = false
    
    override var acceptsFirstResponder: Bool { true }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Semi-transparent overlay
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()
        
        // Draw selection rectangle
        if let start = startPoint, let current = currentPoint {
            let selectionRect = NSRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            
            // Clear the selection area
            NSColor.clear.setFill()
            selectionRect.fill()
            
            // Draw border
            NSColor.white.setStroke()
            let path = NSBezierPath(rect: selectionRect)
            path.lineWidth = 2
            path.stroke()
            
            // Draw size indicator
            let sizeText = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.7)
            ]
            let textSize = sizeText.size(withAttributes: attributes)
            let textRect = NSRect(
                x: selectionRect.midX - textSize.width / 2,
                y: selectionRect.maxY + 8,
                width: textSize.width + 8,
                height: textSize.height + 4
            )
            
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: textRect, xRadius: 4, yRadius: 4).fill()
            
            sizeText.draw(
                at: NSPoint(x: textRect.origin.x + 4, y: textRect.origin.y + 2),
                withAttributes: attributes
            )
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        currentPoint = startPoint
        isSelecting = true
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        currentPoint = event.locationInWindow
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint, let current = currentPoint else {
            return
        }
        
        isSelecting = false
        
        let selectionRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        
        if selectionRect.width > 10 && selectionRect.height > 10 {
            onSelectionComplete?(selectionRect)
        } else {
            onCancel?()
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            onCancel?()
        }
    }
}
