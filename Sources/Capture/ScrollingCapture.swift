import Cocoa

// MARK: - Scrolling Capture Manager
class ScrollingCaptureManager {
    static let shared = ScrollingCaptureManager()
    
    private var captures: [NSImage] = []
    private var isCapturing = false
    private var captureWindow: ScrollingCaptureWindow?
    private var completionHandler: ((NSImage?) -> Void)?
    
    private init() {}
    
    // MARK: - Public Methods
    func startScrollingCapture(completion: @escaping (NSImage?) -> Void) {
        self.completionHandler = completion
        
        DispatchQueue.main.async {
            self.captureWindow = ScrollingCaptureWindow()
            self.captureWindow?.onStart = { [weak self] rect in
                self?.beginScrollingCapture(in: rect)
            }
            self.captureWindow?.onCancel = { [weak self] in
                self?.captureWindow = nil
                completion(nil)
            }
            self.captureWindow?.show()
        }
    }
    
    // MARK: - Private Methods
    private func beginScrollingCapture(in rect: CGRect) {
        captureWindow?.close()
        captures.removeAll()
        isCapturing = true
        
        // Show scrolling capture controls
        DispatchQueue.main.async {
            let controlWindow = ScrollingCaptureControlWindow(captureRect: rect)
            controlWindow.onCapture = { [weak self] in
                self?.captureFrame(in: rect)
            }
            controlWindow.onDone = { [weak self] in
                self?.finishScrollingCapture()
            }
            controlWindow.onCancel = { [weak self] in
                self?.cancelScrollingCapture()
            }
            controlWindow.show()
            self.captureWindow = controlWindow
        }
    }
    
    private func captureFrame(in rect: CGRect) {
        guard let screen = NSScreen.main else { return }
        
        // Convert to screen coordinates
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
        ) else { return }
        
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        captures.append(image)
        
        // Update control window with capture count
        (captureWindow as? ScrollingCaptureControlWindow)?.updateCaptureCount(captures.count)
    }
    
    private func finishScrollingCapture() {
        isCapturing = false
        captureWindow?.close()
        captureWindow = nil
        
        if captures.isEmpty {
            completionHandler?(nil)
            return
        }
        
        // Stitch images together
        let stitchedImage = stitchImages(captures)
        completionHandler?(stitchedImage)
        captures.removeAll()
    }
    
    private func cancelScrollingCapture() {
        isCapturing = false
        captureWindow?.close()
        captureWindow = nil
        captures.removeAll()
        completionHandler?(nil)
    }
    
    private func stitchImages(_ images: [NSImage]) -> NSImage? {
        guard !images.isEmpty else { return nil }
        
        if images.count == 1 {
            return images[0]
        }
        
        // Calculate total height and max width
        var totalHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        
        for image in images {
            totalHeight += image.size.height
            maxWidth = max(maxWidth, image.size.width)
        }
        
        // Create new image
        let newSize = NSSize(width: maxWidth, height: totalHeight)
        let newImage = NSImage(size: newSize)
        
        newImage.lockFocus()
        
        // Draw images from top to bottom
        var yOffset: CGFloat = totalHeight
        for image in images {
            yOffset -= image.size.height
            let rect = NSRect(x: 0, y: yOffset, width: image.size.width, height: image.size.height)
            image.draw(in: rect)
        }
        
        newImage.unlockFocus()
        
        return newImage
    }
}

// MARK: - Scrolling Capture Window
class ScrollingCaptureWindow: NSWindow {
    var onStart: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    
    private var selectionView: ScrollingSelectionView!
    
    init() {
        guard let screen = NSScreen.main else {
            super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            return
        }
        
        super.init(
            contentRect: screen.frame,
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
        
        selectionView = ScrollingSelectionView(frame: screen.frame)
        selectionView.onSelectionComplete = { [weak self] rect in
            self?.onStart?(rect)
        }
        selectionView.onCancel = { [weak self] in
            self?.onCancel?()
        }
        
        self.contentView = selectionView
    }
    
    func show() {
        self.makeKeyAndOrderFront(nil)
        self.makeFirstResponder(selectionView)
    }
}

// MARK: - Scrolling Selection View
class ScrollingSelectionView: NSView {
    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()
        
        // Draw instructions
        let instructionText = "Select the area to capture. Each click will capture a frame. Press Done when finished scrolling."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = instructionText.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2 - 20,
            y: bounds.height - 100,
            width: textSize.width + 40,
            height: textSize.height + 20
        )
        
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: textRect, xRadius: 10, yRadius: 10).fill()
        
        instructionText.draw(
            at: NSPoint(x: textRect.origin.x + 20, y: textRect.origin.y + 10),
            withAttributes: attributes
        )
        
        // Draw selection
        if let start = startPoint, let current = currentPoint {
            let selectionRect = NSRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            
            NSColor.clear.setFill()
            selectionRect.fill()
            
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: selectionRect)
            path.lineWidth = 2
            path.stroke()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        currentPoint = startPoint
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        currentPoint = event.locationInWindow
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint, let current = currentPoint else { return }
        
        let selectionRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        
        if selectionRect.width > 20 && selectionRect.height > 20 {
            onSelectionComplete?(selectionRect)
        } else {
            onCancel?()
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        }
    }
}

// MARK: - Scrolling Capture Control Window
class ScrollingCaptureControlWindow: ScrollingCaptureWindow {
    var onCapture: (() -> Void)?
    var onDone: (() -> Void)?
    
    private var captureRect: CGRect
    private var captureCountLabel: NSTextField!
    private var controlView: NSView!
    
    init(captureRect: CGRect) {
        self.captureRect = captureRect
        super.init()
        setupControlUI()
    }
    
    private func setupControlUI() {
        guard let screen = NSScreen.main else { return }
        
        // Position control bar at bottom of selection
        let controlSize = NSSize(width: 300, height: 60)
        let controlOrigin = NSPoint(
            x: captureRect.midX - controlSize.width / 2,
            y: captureRect.minY - controlSize.height - 20
        )
        
        controlView = NSView(frame: NSRect(origin: .zero, size: controlSize))
        controlView.wantsLayer = true
        controlView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        controlView.layer?.cornerRadius = 12
        
        // Capture count label
        captureCountLabel = NSTextField(labelWithString: "Captures: 0")
        captureCountLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        captureCountLabel.textColor = .white
        captureCountLabel.frame = NSRect(x: 15, y: 20, width: 100, height: 20)
        controlView.addSubview(captureCountLabel)
        
        // Capture button
        let captureButton = NSButton(frame: NSRect(x: 110, y: 15, width: 80, height: 30))
        captureButton.title = "Capture"
        captureButton.bezelStyle = .rounded
        captureButton.target = self
        captureButton.action = #selector(captureClicked)
        controlView.addSubview(captureButton)
        
        // Done button
        let doneButton = NSButton(frame: NSRect(x: 200, y: 15, width: 80, height: 30))
        doneButton.title = "Done"
        doneButton.bezelStyle = .rounded
        doneButton.target = self
        doneButton.action = #selector(doneClicked)
        doneButton.contentTintColor = .systemGreen
        controlView.addSubview(doneButton)
        
        // Create a container view for the control bar
        let containerView = NSView(frame: screen.frame)
        containerView.wantsLayer = true
        
        // Draw the capture area outline
        let outlineLayer = CAShapeLayer()
        outlineLayer.strokeColor = NSColor.systemBlue.cgColor
        outlineLayer.fillColor = nil
        outlineLayer.lineWidth = 3
        outlineLayer.lineDashPattern = [10, 5]
        outlineLayer.path = CGPath(rect: captureRect, transform: nil)
        containerView.layer?.addSublayer(outlineLayer)
        
        controlView.frame.origin = controlOrigin
        containerView.addSubview(controlView)
        
        self.contentView = containerView
        self.ignoresMouseEvents = false
        self.level = .floating
        self.backgroundColor = .clear
    }
    
    func updateCaptureCount(_ count: Int) {
        captureCountLabel.stringValue = "Captures: \(count)"
    }
    
    @objc private func captureClicked() {
        onCapture?()
    }
    
    @objc private func doneClicked() {
        onDone?()
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else if event.keyCode == 49 { // Space
            onCapture?()
        } else if event.keyCode == 36 { // Enter
            onDone?()
        }
    }
}
