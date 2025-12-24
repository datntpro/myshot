import Cocoa
import SwiftUI

class OverlayWindow: NSWindow {
    private let capturedImage: NSImage
    private var hostingController: NSHostingController<OverlayContentView>?
    private var autoHideWorkItem: DispatchWorkItem?
    
    init(image: NSImage) {
        // Create a deep copy by converting to TIFF data and back
        // This ensures completely fresh image with no cached references
        if let tiffData = image.tiffRepresentation,
           let copiedImage = NSImage(data: tiffData) {
            self.capturedImage = copiedImage
            print("📸 OverlayWindow: Created deep copy of image \(copiedImage.size)")
        } else {
            self.capturedImage = image.copy() as! NSImage
            print("⚠️ OverlayWindow: Fallback copy of image \(image.size)")
        }
        
        let overlaySize = NSSize(width: 340, height: 180)
        let screen = NSScreen.main ?? NSScreen.screens.first
        let origin: NSPoint
        
        if let screen = screen {
            origin = NSPoint(
                x: screen.visibleFrame.maxX - overlaySize.width - 20,
                y: screen.visibleFrame.minY + 20
            )
        } else {
            origin = NSPoint(x: 100, y: 100)
        }
        
        let frame = NSRect(origin: origin, size: overlaySize)
        
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.isReleasedWhenClosed = false
        
        setupContent()
        scheduleAutoHide()
    }
    
    deinit {
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
    }
    
    private func setupContent() {
        let contentView = OverlayContentView(
            image: capturedImage,
            onAction: { [weak self] action in
                self?.handleAction(action)
            }
        )
        
        hostingController = NSHostingController(rootView: contentView)
        if let hostingView = hostingController?.view {
            hostingView.frame = NSRect(origin: .zero, size: frame.size)
            self.contentView = hostingView
        }
    }
    
    private func scheduleAutoHide() {
        let workItem = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.isVisible else { return }
                self.fadeOut()
            }
        }
        autoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }
    
    func show() {
        self.alphaValue = 0
        self.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = 1
        }
    }
    
    private func fadeOut() {
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.animator().alphaValue = 0
        }) { [weak self] in
            self?.orderOut(nil)
        }
    }
    
    private func handleAction(_ action: OverlayAction) {
        switch action {
        case .copy:
            copyToClipboard()
        case .save:
            saveToFile()
        case .redact:
            openRedactPreview()
        case .close:
            fadeOut()
        }
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([capturedImage])
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.fadeOut()
        }
    }
    
    private func saveToFile() {
        let filename = "Screenshot-\(formattedTimestamp()).png"
        let saveLocation = URL(fileURLWithPath: SettingsManager.shared.saveLocation)
        let fileURL = saveLocation.appendingPathComponent(filename)
        
        if let tiffData = capturedImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            do {
                try pngData.write(to: fileURL)
                print("✅ Saved to \(fileURL.path)")
                
                // Show in Finder
                NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
            } catch {
                print("❌ Failed to save: \(error)")
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.fadeOut()
        }
    }
    
    private func formattedTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter.string(from: Date())
    }
    
    private func openRedactPreview() {
        // Cancel auto-hide
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
        
        print("🔍 Starting sensitive data detection...")
        print("   Image size: \(capturedImage.size)")
        
        // Detect sensitive data
        SensitiveDataDetector.shared.detectInImage(capturedImage) { [weak self] matches in
            guard let self = self else { return }
            
            print("📊 Detection complete: \(matches.count) matches found")
            for match in matches {
                print("   - \(match.type.rawValue): \(match.maskedText)")
            }
            
            if matches.isEmpty {
                // No sensitive data found, show alert
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "No Sensitive Data Found"
                    alert.informativeText = "No credit card numbers, API keys, or passwords were detected in this screenshot.\n\nTip: The text must be clearly visible and match known patterns."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                return
            }
            
            // Show redact preview window
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                let previewWindow = RedactPreviewWindow(
                    image: self.capturedImage,
                    matches: matches
                ) { [weak self] redactedImage in
                    guard let redactedImage = redactedImage else { return }
                    
                    // Copy redacted image to clipboard
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([redactedImage])
                    
                    print("✅ Redacted image copied to clipboard")
                    
                    // Save to history
                    CaptureHistoryManager.shared.addCapture(image: redactedImage)
                    
                    // Show user feedback
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Redaction Complete! ✅"
                        alert.informativeText = "The redacted image has been:\n\n• Copied to clipboard (⌘V to paste)\n• Saved to capture history"
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                    
                    self?.fadeOut()
                }
                
                self.orderOut(nil)
                previewWindow.show()
            }
        }
    }
}

enum OverlayAction {
    case copy, save, redact, close
}

struct OverlayContentView: View {
    let image: NSImage
    let onAction: (OverlayAction) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Button(action: { onAction(.close) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
                .padding(6)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            HStack(spacing: 8) {
                OverlayButton(icon: "doc.on.clipboard", label: "Copy") {
                    onAction(.copy)
                }
                OverlayButton(icon: "square.and.arrow.down", label: "Save") {
                    onAction(.save)
                }
                OverlayButton(icon: "eye.slash", label: "Redact") {
                    onAction(.redact)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }
}

struct OverlayButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isHovering ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundColor(.white)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
