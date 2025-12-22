import Cocoa
import ScreenCaptureKit
import AVFoundation
import CoreGraphics
import ImageIO

class ScreenRecordingManager: NSObject {
    static let shared = ScreenRecordingManager()
    
    private var isRecording = false
    private var recordingAsGif = false
    private var recordingWindow: RecordingControlWindow?
    private var selectionWindow: RecordingSelectionWindow?
    
    // Video recording
    private var videoWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var captureSession: SCStream?
    private var streamOutput: RecordingStreamOutput?
    private var startTime: CMTime?
    
    // GIF recording
    private var gifFrames: [CGImage] = []
    private var gifTimer: Timer?
    
    private var recordingRect: CGRect = .zero
    private var outputURL: URL?
    
    private override init() {
        super.init()
    }
    
    func startRecording(asGif: Bool) {
        recordingAsGif = asGif
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let window = RecordingSelectionWindow()
            self.selectionWindow = window
            
            window.onSelectionComplete = { [weak self] rect in
                self?.beginRecording(in: rect)
            }
            window.onCancel = { [weak self] in
                self?.selectionWindow?.orderOut(nil)
                self?.selectionWindow = nil
            }
            window.show()
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        recordingWindow?.orderOut(nil)
        recordingWindow = nil
        
        if recordingAsGif {
            finishGifRecording()
        } else {
            finishVideoRecording()
        }
    }
    
    private func beginRecording(in rect: CGRect) {
        selectionWindow?.orderOut(nil)
        selectionWindow = nil
        
        recordingRect = rect
        isRecording = true
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let ext = recordingAsGif ? "gif" : "mp4"
        let filename = "Recording-\(timestamp).\(ext)"
        
        let saveLocation = URL(fileURLWithPath: SettingsManager.shared.saveLocation)
        outputURL = saveLocation.appendingPathComponent(filename)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let window = RecordingControlWindow(rect: rect)
            self.recordingWindow = window
            window.onStop = { [weak self] in
                self?.stopRecording()
            }
            window.show()
        }
        
        if recordingAsGif {
            startGifRecording()
        } else {
            startVideoRecording()
        }
    }
    
    // MARK: - Video Recording
    private func startVideoRecording() {
        guard let url = outputURL else { return }
        
        try? FileManager.default.removeItem(at: url)
        
        do {
            videoWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
            
            // Use screen scale for high quality capture
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let width = Int(recordingRect.width * scale)
            let height = Int(recordingRect.height * scale)
            
            // Use settings for quality
            let bitrate = SettingsManager.shared.videoBitrate
            let fps = SettingsManager.shared.videoFPS
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoMaxKeyFrameIntervalKey: fps
                ]
            ]
            
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
            
            if let input = videoInput {
                pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: input,
                    sourcePixelBufferAttributes: pixelBufferAttributes
                )
                videoWriter?.add(input)
            }
            
            videoWriter?.startWriting()
            startTime = nil
            
            startScreenCaptureStream()
            
        } catch {
            print("Failed to start video recording: \(error)")
            stopRecording()
        }
    }
    
    private func startScreenCaptureStream() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                
                guard let display = content.displays.first else {
                    print("No display found")
                    return
                }
                
                let filter = SCContentFilter(display: display, excludingWindows: [])
                
                // High quality capture configuration
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                let fps = SettingsManager.shared.videoFPS
                let config = SCStreamConfiguration()
                config.width = Int(recordingRect.width * scale)
                config.height = Int(recordingRect.height * scale)
                config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
                config.showsCursor = true
                config.sourceRect = recordingRect
                config.scalesToFit = false
                
                let output = RecordingStreamOutput()
                self.streamOutput = output
                output.onFrame = { [weak self] sampleBuffer in
                    self?.processVideoFrame(sampleBuffer)
                }
                
                captureSession = SCStream(filter: filter, configuration: config, delegate: nil)
                try captureSession?.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "recording.queue"))
                try await captureSession?.startCapture()
                
            } catch {
                print("Failed to start screen capture: \(error)")
                await MainActor.run { stopRecording() }
            }
        }
    }
    
    private func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let videoInput = videoInput,
              let pixelBufferAdaptor = pixelBufferAdaptor,
              videoInput.isReadyForMoreMediaData else { return }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if startTime == nil {
            startTime = timestamp
            videoWriter?.startSession(atSourceTime: timestamp)
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        pixelBufferAdaptor.append(imageBuffer, withPresentationTime: timestamp)
    }
    
    private func finishVideoRecording() {
        Task {
            try? await captureSession?.stopCapture()
            captureSession = nil
            
            await MainActor.run { [weak self] in
                self?.videoInput?.markAsFinished()
                
                self?.videoWriter?.finishWriting { [weak self] in
                    DispatchQueue.main.async {
                        if let url = self?.outputURL {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                        }
                        self?.videoWriter = nil
                        self?.videoInput = nil
                        self?.pixelBufferAdaptor = nil
                    }
                }
            }
        }
    }
    
    // MARK: - GIF Recording
    private func startGifRecording() {
        gifFrames.removeAll()
        
        let fps = 10.0
        gifTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            self?.captureGifFrame()
        }
    }
    
    private func captureGifFrame() {
        guard isRecording else {
            gifTimer?.invalidate()
            return
        }
        
        guard let screen = NSScreen.main else { return }
        
        let screenHeight = screen.frame.height
        let flippedRect = CGRect(
            x: recordingRect.origin.x,
            y: screenHeight - recordingRect.origin.y - recordingRect.height,
            width: recordingRect.width,
            height: recordingRect.height
        )
        
        guard let cgImage = CGWindowListCreateImage(
            flippedRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else { return }
        
        gifFrames.append(cgImage)
    }
    
    private func finishGifRecording() {
        gifTimer?.invalidate()
        gifTimer = nil
        
        guard let url = outputURL, !gifFrames.isEmpty else { return }
        
        let frames = gifFrames
        gifFrames.removeAll()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.createGif(from: frames, outputURL: url)
            
            DispatchQueue.main.async {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            }
        }
    }
    
    private func createGif(from frames: [CGImage], outputURL: URL) {
        let frameDelay = 0.1
        
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay
            ]
        ]
        
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            "com.compuserve.gif" as CFString,
            frames.count,
            nil
        ) else { return }
        
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)
        
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }
        
        CGImageDestinationFinalize(destination)
    }
}

// MARK: - Recording Stream Output
class RecordingStreamOutput: NSObject, SCStreamOutput {
    var onFrame: ((CMSampleBuffer) -> Void)?
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .screen {
            onFrame?(sampleBuffer)
        }
    }
}

// MARK: - Recording Selection Window
class RecordingSelectionWindow: NSWindow {
    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    
    private var selectionView: RecordingSelectionView?
    
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
        
        let view = RecordingSelectionView(frame: frame)
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

// MARK: - Recording Selection View
class RecordingSelectionView: NSView {
    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let dimColor = NSColor.black.withAlphaComponent(0.6)
        
        if let start = startPoint, let current = currentPoint {
            let selectionRect = NSRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            
            // Draw 4 dim rectangles around selection (not on selection)
            dimColor.setFill()
            
            // Left rectangle
            NSRect(x: 0, y: 0, width: selectionRect.minX, height: bounds.height).fill()
            // Right rectangle
            NSRect(x: selectionRect.maxX, y: 0, width: bounds.width - selectionRect.maxX, height: bounds.height).fill()
            // Bottom rectangle (between left and right)
            NSRect(x: selectionRect.minX, y: 0, width: selectionRect.width, height: selectionRect.minY).fill()
            // Top rectangle (between left and right)
            NSRect(x: selectionRect.minX, y: selectionRect.maxY, width: selectionRect.width, height: bounds.height - selectionRect.maxY).fill()
            
            // Draw red border around selection
            NSColor.red.setStroke()
            let path = NSBezierPath(rect: selectionRect)
            path.lineWidth = 3
            path.stroke()
            
            // Draw size indicator
            let text = "🔴 Recording: \(Int(selectionRect.width)) × \(Int(selectionRect.height))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let textSize = text.size(withAttributes: attributes)
            let textRect = NSRect(
                x: selectionRect.midX - textSize.width / 2 - 12,
                y: selectionRect.maxY + 15,
                width: textSize.width + 24,
                height: textSize.height + 12
            )
            
            NSColor.red.withAlphaComponent(0.95).setFill()
            NSBezierPath(roundedRect: textRect, xRadius: 8, yRadius: 8).fill()
            
            text.draw(at: NSPoint(x: textRect.origin.x + 12, y: textRect.origin.y + 6), withAttributes: attributes)
        } else {
            // Initial state - dim entire screen with instructions
            dimColor.setFill()
            bounds.fill()
            
            let instructionText = "Drag to select recording area • Press ESC to cancel"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let textSize = instructionText.size(withAttributes: attributes)
            let textPoint = NSPoint(
                x: bounds.midX - textSize.width / 2,
                y: bounds.midY
            )
            
            let bgRect = NSRect(
                x: textPoint.x - 20,
                y: textPoint.y - 10,
                width: textSize.width + 40,
                height: textSize.height + 20
            )
            NSColor.black.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: bgRect, xRadius: 10, yRadius: 10).fill()
            
            instructionText.draw(at: textPoint, withAttributes: attributes)
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
        
        if selectionRect.width > 50 && selectionRect.height > 50 {
            onSelectionComplete?(selectionRect)
        } else {
            onCancel?()
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
    }
}

// MARK: - Recording Control Window
class RecordingControlWindow: NSWindow {
    var onStop: (() -> Void)?
    
    private var recordingRect: CGRect
    private var elapsedTime: TimeInterval = 0
    private var timer: Timer?
    private var timeLabel: NSTextField?
    
    init(rect: CGRect) {
        self.recordingRect = rect
        
        let size = NSSize(width: 220, height: 60)
        
        // Position at top center of screen for maximum visibility
        let screen = NSScreen.main ?? NSScreen.screens.first
        let origin: NSPoint
        if let screen = screen {
            origin = NSPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height - 50
            )
        } else {
            origin = NSPoint(x: rect.midX - size.width / 2, y: rect.maxY + 20)
        }
        
        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating + 1000  // Very high level to ensure visibility
        self.isOpaque = false
        self.backgroundColor = .clear
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        
        setupUI()
    }
    
    private func setupUI() {
        let containerView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.95).cgColor
        containerView.layer?.cornerRadius = 15
        containerView.layer?.shadowColor = NSColor.black.cgColor
        containerView.layer?.shadowOpacity = 0.5
        containerView.layer?.shadowRadius = 10
        containerView.layer?.shadowOffset = CGSize(width: 0, height: -3)
        
        // Recording indicator dot with animation
        let recordDot = NSView(frame: NSRect(x: 15, y: 22, width: 16, height: 16))
        recordDot.wantsLayer = true
        recordDot.layer?.backgroundColor = NSColor.white.cgColor
        recordDot.layer?.cornerRadius = 8
        
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.3
        animation.duration = 0.5
        animation.autoreverses = true
        animation.repeatCount = .infinity
        recordDot.layer?.add(animation, forKey: "pulse")
        containerView.addSubview(recordDot)
        
        // Time label
        let label = NSTextField(labelWithString: "00:00")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        label.textColor = .white
        label.frame = NSRect(x: 40, y: 17, width: 70, height: 26)
        containerView.addSubview(label)
        self.timeLabel = label
        
        // Stop button
        let stopButton = NSButton(frame: NSRect(x: 120, y: 12, width: 90, height: 36))
        stopButton.title = "⏹ STOP"
        stopButton.bezelStyle = .rounded
        stopButton.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        stopButton.target = self
        stopButton.action = #selector(stopClicked)
        stopButton.wantsLayer = true
        stopButton.layer?.backgroundColor = NSColor.white.cgColor
        stopButton.layer?.cornerRadius = 8
        containerView.addSubview(stopButton)
        
        contentView = containerView
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTime()
        }
    }
    
    private func updateTime() {
        elapsedTime += 1
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        timeLabel?.stringValue = String(format: "%02d:%02d", minutes, seconds)
    }
    
    @objc private func stopClicked() {
        timer?.invalidate()
        onStop?()
    }
    
    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
