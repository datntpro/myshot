import Cocoa
import SwiftUI

// MARK: - Annotation State
class AnnotationState: ObservableObject {
    static let shared = AnnotationState()
    
    @Published var currentImage: NSImage?
    @Published var selectedTool: AnnotationTool = .arrow
    @Published var strokeColor: NSColor = .red
    @Published var strokeWidth: CGFloat = 3
    @Published var fontSize: CGFloat = 16
    
    private init() {}
    
    func setImage(_ image: NSImage) {
        currentImage = image
    }
}

// MARK: - Annotation Tool
enum AnnotationTool: String, CaseIterable {
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case filledRect = "Filled Rect"
    case ellipse = "Ellipse"
    case filledEllipse = "Filled Ellipse"
    case line = "Line"
    case pencil = "Pencil"
    case text = "Text"
    case highlight = "Highlight"
    case blur = "Blur"
    case spotlight = "Spotlight"
    case number = "Number"
    case emoji = "Emoji"
    case redact = "Redact"
    case crop = "Crop"
    
    var icon: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .filledRect: return "rectangle.fill"
        case .ellipse: return "circle"
        case .filledEllipse: return "circle.fill"
        case .line: return "line.diagonal"
        case .pencil: return "pencil"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .blur: return "checkerboard.rectangle"
        case .spotlight: return "sun.max"
        case .number: return "number.circle"
        case .emoji: return "face.smiling"
        case .redact: return "eye.slash"
        case .crop: return "crop"
        }
    }
    
    var shortcut: String {
        switch self {
        case .arrow: return "1"
        case .rectangle: return "2"
        case .filledRect: return "3"
        case .ellipse: return "4"
        case .filledEllipse: return "5"
        case .line: return "6"
        case .pencil: return "7"
        case .text: return "T"
        case .highlight: return "H"
        case .blur: return "B"
        case .spotlight: return "S"
        case .number: return "N"
        case .emoji: return "E"
        case .redact: return "R"
        case .crop: return "C"
        }
    }
}

// MARK: - Annotation Item
struct AnnotationItem: Identifiable {
    let id = UUID()
    var tool: AnnotationTool
    var startPoint: CGPoint
    var endPoint: CGPoint
    var color: NSColor
    var strokeWidth: CGFloat
    var text: String?
    var number: Int?
    var emoji: String?
    var pathPoints: [CGPoint] = []
    var fontSize: CGFloat = 16
}

// MARK: - Common Emojis
let commonEmojis = ["👍", "👎", "❤️", "⭐", "✅", "❌", "⚠️", "💡", "🔥", "🎯", "📌", "🔍", "💬", "✨", "🚀", "🐛"]

// MARK: - Annotation Window
class AnnotationWindow: NSWindow {
    private var image: NSImage
    private var hostingView: NSHostingView<AnnotationEditorContentView>?
    
    // Self-retain to prevent deallocation while window is open
    private static var activeWindows: [AnnotationWindow] = []
    
    init(image: NSImage) {
        self.image = image
        
        let screenSize = NSScreen.main?.frame.size ?? NSSize(width: 1200, height: 800)
        let maxWidth = min(image.size.width + 100, screenSize.width * 0.9)
        let maxHeight = min(image.size.height + 200, screenSize.height * 0.9)
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: maxWidth, height: maxHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Annotation Editor"
        self.center()
        self.isReleasedWhenClosed = false
        self.delegate = self
        
        // Retain self while window is open
        AnnotationWindow.activeWindows.append(self)
        
        setupContent()
    }
    
    private func setupContent() {
        let editorView = AnnotationEditorContentView(
            image: image,
            onSave: { [weak self] editedImage in
                self?.saveImage(editedImage)
            },
            onCopy: { [weak self] editedImage in
                self?.copyImage(editedImage)
            }
        )
        
        hostingView = NSHostingView(rootView: editorView)
        contentView = hostingView
    }
    
    private func saveImage(_ image: NSImage) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "Annotated-\(Date().formatted(.dateTime.year().month().day().hour().minute().second()))"
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }
    }
    
    private func copyImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
    
    private func cleanup() {
        // Clear content first to release SwiftUI views
        hostingView = nil
        contentView = nil
        
        // Remove from active windows after a delay
        DispatchQueue.main.async { [weak self] in
            if let self = self, let index = AnnotationWindow.activeWindows.firstIndex(where: { $0 === self }) {
                AnnotationWindow.activeWindows.remove(at: index)
            }
        }
    }
}

extension AnnotationWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        cleanup()
    }
}

// MARK: - Annotation Editor Content View
struct AnnotationEditorContentView: View {
    let image: NSImage
    let onSave: (NSImage) -> Void
    let onCopy: (NSImage) -> Void
    
    @State private var selectedTool: AnnotationTool = .arrow
    @State private var annotations: [AnnotationItem] = []
    @State private var currentAnnotation: AnnotationItem?
    @State private var strokeColor: Color = .red
    @State private var strokeWidth: CGFloat = 3
    @State private var fontSize: CGFloat = 16
    @State private var numberCounter: Int = 1
    @State private var zoomScale: CGFloat = 1.0
    
    // Text input
    @State private var showTextInput = false
    @State private var textInputValue = ""
    @State private var textInputPosition: CGPoint = .zero
    
    // Emoji picker
    @State private var showEmojiPicker = false
    @State private var emojiPosition: CGPoint = .zero
    
    // Crop
    @State private var cropRect: CGRect?
    @State private var isCropping = false
    
    // Undo history
    @State private var undoHistory: [[AnnotationItem]] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarView
            
            Divider()
            
            // Secondary toolbar for zoom
            zoomToolbar
            
            Divider()
            
            // Canvas
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        AnnotationCanvasView(
                            image: image,
                            annotations: $annotations,
                            currentAnnotation: $currentAnnotation,
                            selectedTool: selectedTool,
                            strokeColor: NSColor(strokeColor),
                            strokeWidth: strokeWidth,
                            fontSize: fontSize,
                            numberCounter: $numberCounter,
                            onTextRequest: { point in
                                textInputPosition = point
                                textInputValue = ""
                                showTextInput = true
                            },
                            onEmojiRequest: { point in
                                emojiPosition = point
                                showEmojiPicker = true
                            },
                            cropRect: $cropRect,
                            isCropping: $isCropping
                        )
                        .scaleEffect(zoomScale)
                    }
                    .frame(width: image.size.width * zoomScale, height: image.size.height * zoomScale)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showTextInput) {
            TextInputSheet(text: $textInputValue) { finalText in
                if !finalText.isEmpty {
                    let annotation = AnnotationItem(
                        tool: .text,
                        startPoint: textInputPosition,
                        endPoint: textInputPosition,
                        color: NSColor(strokeColor),
                        strokeWidth: strokeWidth,
                        text: finalText,
                        fontSize: fontSize
                    )
                    saveToUndoHistory()
                    annotations.append(annotation)
                }
                showTextInput = false
            }
        }
        .sheet(isPresented: $showEmojiPicker) {
            EmojiPickerSheet { selectedEmoji in
                if let emoji = selectedEmoji {
                    let annotation = AnnotationItem(
                        tool: .emoji,
                        startPoint: emojiPosition,
                        endPoint: emojiPosition,
                        color: .clear,
                        strokeWidth: 0,
                        emoji: emoji,
                        fontSize: fontSize * 2
                    )
                    saveToUndoHistory()
                    annotations.append(annotation)
                }
                showEmojiPicker = false
            }
        }
    }
    
    private var toolbarView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Drawing tools
                HStack(spacing: 2) {
                    ForEach([AnnotationTool.arrow, .rectangle, .filledRect, .ellipse, .filledEllipse, .line, .pencil], id: \.self) { tool in
                        ToolButton(tool: tool, isSelected: selectedTool == tool) {
                            selectedTool = tool
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Text & markers
                HStack(spacing: 2) {
                    ForEach([AnnotationTool.text, .number, .emoji], id: \.self) { tool in
                        ToolButton(tool: tool, isSelected: selectedTool == tool) {
                            selectedTool = tool
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Effects
                HStack(spacing: 2) {
                    ForEach([AnnotationTool.highlight, .blur, .spotlight, .redact], id: \.self) { tool in
                        ToolButton(tool: tool, isSelected: selectedTool == tool) {
                            selectedTool = tool
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Crop
                ToolButton(tool: .crop, isSelected: selectedTool == .crop) {
                    selectedTool = .crop
                    isCropping = true
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Divider().frame(height: 24)
                
                // Color picker
                ColorPicker("", selection: $strokeColor)
                    .labelsHidden()
                    .frame(width: 36)
                
                // Stroke width
                HStack(spacing: 4) {
                    Image(systemName: "lineweight")
                        .font(.caption)
                    Slider(value: $strokeWidth, in: 1...15, step: 1)
                        .frame(width: 60)
                    Text("\(Int(strokeWidth))")
                        .font(.caption)
                        .frame(width: 16)
                }
                
                // Font size (for text/emoji)
                HStack(spacing: 4) {
                    Image(systemName: "textformat.size")
                        .font(.caption)
                    Slider(value: $fontSize, in: 10...48, step: 2)
                        .frame(width: 60)
                    Text("\(Int(fontSize))")
                        .font(.caption)
                        .frame(width: 20)
                }
                
                Spacer()
                
                // Undo
                Button(action: performUndo) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(annotations.isEmpty && undoHistory.isEmpty)
                .help("Undo (⌘Z)")
                
                // Clear all
                Button(action: {
                    saveToUndoHistory()
                    annotations.removeAll()
                    numberCounter = 1
                }) {
                    Image(systemName: "trash")
                }
                .disabled(annotations.isEmpty)
                .help("Clear All")
                
                Divider().frame(height: 24)
                
                // Apply crop
                if isCropping && cropRect != nil {
                    Button("Apply Crop") {
                        applyCrop()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Cancel") {
                        cropRect = nil
                        isCropping = false
                    }
                    .buttonStyle(.bordered)
                }
                
                // Save/Copy
                Button("Copy") {
                    let renderedImage = renderAnnotatedImage()
                    onCopy(renderedImage)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                
                Button("Save") {
                    let renderedImage = renderAnnotatedImage()
                    onSave(renderedImage)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
    
    private var zoomToolbar: some View {
        HStack {
            Button(action: { zoomScale = max(0.25, zoomScale - 0.25) }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("-", modifiers: .command)
            
            Text("\(Int(zoomScale * 100))%")
                .font(.caption)
                .frame(width: 50)
            
            Button(action: { zoomScale = min(4.0, zoomScale + 0.25) }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("=", modifiers: .command)
            
            Button("Fit") {
                zoomScale = 1.0
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("0", modifiers: .command)
            
            Spacer()
            
            Text("Tool: \(selectedTool.rawValue) (\(selectedTool.shortcut))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private func saveToUndoHistory() {
        undoHistory.append(annotations)
        if undoHistory.count > 50 {
            undoHistory.removeFirst()
        }
    }
    
    private func performUndo() {
        if !annotations.isEmpty {
            saveToUndoHistory()
            annotations.removeLast()
        } else if let lastState = undoHistory.popLast() {
            annotations = lastState
        }
    }
    
    private func applyCrop() {
        guard let rect = cropRect else { return }
        
        // Create cropped image
        let croppedImage = NSImage(size: rect.size)
        croppedImage.lockFocus()
        
        let sourceRect = NSRect(
            x: rect.origin.x,
            y: image.size.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        
        image.draw(
            in: NSRect(origin: .zero, size: rect.size),
            from: sourceRect,
            operation: .copy,
            fraction: 1.0
        )
        
        croppedImage.unlockFocus()
        
        // Save cropped image
        onSave(croppedImage)
        cropRect = nil
        isCropping = false
    }
    
    private func renderAnnotatedImage() -> NSImage {
        let newImage = NSImage(size: image.size)
        newImage.lockFocus()
        
        // Draw original image
        image.draw(in: NSRect(origin: .zero, size: image.size))
        
        // Draw annotations
        for annotation in annotations {
            drawAnnotation(annotation)
        }
        
        newImage.unlockFocus()
        return newImage
    }
    
    private func drawAnnotation(_ annotation: AnnotationItem) {
        annotation.color.setStroke()
        annotation.color.setFill()
        
        switch annotation.tool {
        case .arrow:
            drawArrow(from: annotation.startPoint, to: annotation.endPoint, width: annotation.strokeWidth, color: annotation.color)
        case .rectangle:
            let rect = rectFrom(start: annotation.startPoint, end: annotation.endPoint)
            let path = NSBezierPath(rect: rect)
            path.lineWidth = annotation.strokeWidth
            path.stroke()
        case .filledRect:
            let rect = rectFrom(start: annotation.startPoint, end: annotation.endPoint)
            annotation.color.withAlphaComponent(0.3).setFill()
            NSBezierPath(rect: rect).fill()
            annotation.color.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = annotation.strokeWidth
            path.stroke()
        case .ellipse:
            let rect = rectFrom(start: annotation.startPoint, end: annotation.endPoint)
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = annotation.strokeWidth
            path.stroke()
        case .filledEllipse:
            let rect = rectFrom(start: annotation.startPoint, end: annotation.endPoint)
            annotation.color.withAlphaComponent(0.3).setFill()
            NSBezierPath(ovalIn: rect).fill()
            annotation.color.setStroke()
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = annotation.strokeWidth
            path.stroke()
        case .line:
            let path = NSBezierPath()
            path.move(to: annotation.startPoint)
            path.line(to: annotation.endPoint)
            path.lineWidth = annotation.strokeWidth
            path.stroke()
        case .pencil:
            guard annotation.pathPoints.count > 1 else { break }
            let path = NSBezierPath()
            path.move(to: annotation.pathPoints[0])
            for i in 1..<annotation.pathPoints.count {
                path.line(to: annotation.pathPoints[i])
            }
            path.lineWidth = annotation.strokeWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        case .highlight:
            let rect = rectFrom(start: annotation.startPoint, end: annotation.endPoint)
            annotation.color.withAlphaComponent(0.3).setFill()
            NSBezierPath(rect: rect).fill()
        case .blur, .redact:
            drawPixelatedBlur(annotation)
        case .spotlight:
            drawSpotlight(annotation)
        case .text:
            if let text = annotation.text {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: annotation.fontSize),
                    .foregroundColor: annotation.color
                ]
                text.draw(at: annotation.startPoint, withAttributes: attributes)
            }
        case .number:
            if let number = annotation.number {
                let size: CGFloat = 28
                let rect = NSRect(
                    x: annotation.startPoint.x - size/2,
                    y: annotation.startPoint.y - size/2,
                    width: size,
                    height: size
                )
                annotation.color.setFill()
                NSBezierPath(ovalIn: rect).fill()
                
                let text = "\(number)"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 16),
                    .foregroundColor: NSColor.white
                ]
                let textSize = text.size(withAttributes: attributes)
                let textPoint = NSPoint(
                    x: annotation.startPoint.x - textSize.width/2,
                    y: annotation.startPoint.y - textSize.height/2
                )
                text.draw(at: textPoint, withAttributes: attributes)
            }
        case .emoji:
            if let emoji = annotation.emoji {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: annotation.fontSize)
                ]
                let emojiSize = emoji.size(withAttributes: attributes)
                let drawPoint = NSPoint(
                    x: annotation.startPoint.x - emojiSize.width/2,
                    y: annotation.startPoint.y - emojiSize.height/2
                )
                emoji.draw(at: drawPoint, withAttributes: attributes)
            }
        case .crop:
            break
        }
    }
    
    private func drawSpotlight(_ annotation: AnnotationItem) {
        let spotlightRect = rectFrom(start: annotation.startPoint, end: annotation.endPoint)
        
        // Draw semi-transparent overlay on entire image except spotlight area
        NSColor.black.withAlphaComponent(0.6).setFill()
        
        // Top
        NSBezierPath(rect: NSRect(x: 0, y: spotlightRect.maxY, width: image.size.width, height: image.size.height - spotlightRect.maxY)).fill()
        // Bottom
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: image.size.width, height: spotlightRect.minY)).fill()
        // Left
        NSBezierPath(rect: NSRect(x: 0, y: spotlightRect.minY, width: spotlightRect.minX, height: spotlightRect.height)).fill()
        // Right
        NSBezierPath(rect: NSRect(x: spotlightRect.maxX, y: spotlightRect.minY, width: image.size.width - spotlightRect.maxX, height: spotlightRect.height)).fill()
        
        // Draw border around spotlight
        annotation.color.setStroke()
        let borderPath = NSBezierPath(rect: spotlightRect)
        borderPath.lineWidth = 2
        borderPath.stroke()
    }
    
    private func drawPixelatedBlur(_ annotation: AnnotationItem) {
        let rect = rectFrom(start: annotation.startPoint, end: annotation.endPoint)
        guard rect.width > 0 && rect.height > 0 else { return }
        
        let pixelSize: CGFloat = annotation.tool == .redact ? 8 : 12
        
        for y in stride(from: rect.minY, to: rect.maxY, by: pixelSize) {
            for x in stride(from: rect.minX, to: rect.maxX, by: pixelSize) {
                let pixelRect = NSRect(x: x, y: y, width: pixelSize, height: pixelSize)
                
                if annotation.tool == .redact {
                    // Solid black for redact
                    NSColor.black.setFill()
                } else {
                    // Random gray for blur
                    let grayValue = CGFloat.random(in: 0.4...0.7)
                    NSColor(white: grayValue, alpha: 0.95).setFill()
                }
                NSBezierPath(rect: pixelRect).fill()
            }
        }
    }
    
    private func rectFrom(start: CGPoint, end: CGPoint) -> NSRect {
        return NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
    
    private func drawArrow(from start: CGPoint, to end: CGPoint, width: CGFloat, color: NSColor) {
        color.setStroke()
        
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
        
        // Arrow head
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 15 + width
        let arrowAngle: CGFloat = .pi / 6
        
        let point1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let point2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        
        color.setFill()
        let arrowPath = NSBezierPath()
        arrowPath.move(to: end)
        arrowPath.line(to: point1)
        arrowPath.line(to: point2)
        arrowPath.close()
        arrowPath.fill()
    }
}

// MARK: - Text Input Sheet
struct TextInputSheet: View {
    @Binding var text: String
    let onComplete: (String) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Enter Text")
                .font(.headline)
            
            TextField("Type here...", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            
            HStack {
                Button("Cancel") {
                    onComplete("")
                }
                .keyboardShortcut(.escape)
                
                Button("Add") {
                    onComplete(text)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(text.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 350)
    }
}

// MARK: - Emoji Picker Sheet
struct EmojiPickerSheet: View {
    let onSelect: (String?) -> Void
    
    let columns = [GridItem(.adaptive(minimum: 44))]
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Emoji")
                .font(.headline)
            
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(commonEmojis, id: \.self) { emoji in
                    Button(action: { onSelect(emoji) }) {
                        Text(emoji)
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Button("Cancel") {
                onSelect(nil)
            }
            .keyboardShortcut(.escape)
        }
        .padding(24)
        .frame(width: 300)
    }
}

// MARK: - Tool Button
struct ToolButton: View {
    let tool: AnnotationTool
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: tool.icon)
                .font(.system(size: 13))
                .frame(width: 26, height: 26)
                .background(isSelected ? Color.accentColor : Color.clear)
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("\(tool.rawValue) (\(tool.shortcut))")
    }
}

// MARK: - Notification for Undo
extension Notification.Name {
    static let undoAnnotation = Notification.Name("undoAnnotation")
}

// MARK: - Annotation Canvas View
struct AnnotationCanvasView: NSViewRepresentable {
    let image: NSImage
    @Binding var annotations: [AnnotationItem]
    @Binding var currentAnnotation: AnnotationItem?
    let selectedTool: AnnotationTool
    let strokeColor: NSColor
    let strokeWidth: CGFloat
    let fontSize: CGFloat
    @Binding var numberCounter: Int
    let onTextRequest: (CGPoint) -> Void
    let onEmojiRequest: (CGPoint) -> Void
    @Binding var cropRect: CGRect?
    @Binding var isCropping: Bool
    
    func makeNSView(context: Context) -> AnnotationNSView {
        let view = AnnotationNSView(image: image)
        view.delegate = context.coordinator
        return view
    }
    
    func updateNSView(_ nsView: AnnotationNSView, context: Context) {
        nsView.annotations = annotations
        nsView.currentAnnotation = currentAnnotation
        nsView.cropRect = cropRect
        nsView.isCropping = isCropping
        nsView.needsDisplay = true
        context.coordinator.selectedTool = selectedTool
        context.coordinator.strokeColor = strokeColor
        context.coordinator.strokeWidth = strokeWidth
        context.coordinator.fontSize = fontSize
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, AnnotationNSViewDelegate {
        var parent: AnnotationCanvasView
        var selectedTool: AnnotationTool = .arrow
        var strokeColor: NSColor = .red
        var strokeWidth: CGFloat = 3
        var fontSize: CGFloat = 16
        
        init(_ parent: AnnotationCanvasView) {
            self.parent = parent
        }
        
        func didStartAnnotation(at point: CGPoint) {
            switch selectedTool {
            case .text:
                parent.onTextRequest(point)
            case .emoji:
                parent.onEmojiRequest(point)
            case .number:
                let annotation = AnnotationItem(
                    tool: selectedTool,
                    startPoint: point,
                    endPoint: point,
                    color: strokeColor,
                    strokeWidth: strokeWidth,
                    number: parent.numberCounter,
                    fontSize: fontSize
                )
                parent.annotations.append(annotation)
                parent.numberCounter += 1
            case .pencil:
                var annotation = AnnotationItem(
                    tool: selectedTool,
                    startPoint: point,
                    endPoint: point,
                    color: strokeColor,
                    strokeWidth: strokeWidth,
                    fontSize: fontSize
                )
                annotation.pathPoints = [point]
                parent.currentAnnotation = annotation
            case .crop:
                parent.cropRect = CGRect(origin: point, size: .zero)
            default:
                parent.currentAnnotation = AnnotationItem(
                    tool: selectedTool,
                    startPoint: point,
                    endPoint: point,
                    color: strokeColor,
                    strokeWidth: strokeWidth,
                    fontSize: fontSize
                )
            }
        }
        
        func didUpdateAnnotation(to point: CGPoint) {
            if selectedTool == .crop {
                if let startPoint = parent.cropRect?.origin {
                    parent.cropRect = CGRect(
                        x: min(startPoint.x, point.x),
                        y: min(startPoint.y, point.y),
                        width: abs(point.x - startPoint.x),
                        height: abs(point.y - startPoint.y)
                    )
                }
            } else if parent.currentAnnotation?.tool == .pencil {
                parent.currentAnnotation?.pathPoints.append(point)
                parent.currentAnnotation?.endPoint = point
            } else {
                parent.currentAnnotation?.endPoint = point
            }
        }
        
        func didEndAnnotation(at point: CGPoint) {
            if selectedTool == .crop {
                // Keep crop rect displayed
                return
            }
            
            if var annotation = parent.currentAnnotation {
                annotation.endPoint = point
                if annotation.tool == .pencil {
                    annotation.pathPoints.append(point)
                }
                parent.annotations.append(annotation)
                parent.currentAnnotation = nil
            }
        }
    }
}

// MARK: - Annotation NSView
protocol AnnotationNSViewDelegate: AnyObject {
    func didStartAnnotation(at point: CGPoint)
    func didUpdateAnnotation(to point: CGPoint)
    func didEndAnnotation(at point: CGPoint)
}

class AnnotationNSView: NSView {
    let image: NSImage
    var annotations: [AnnotationItem] = []
    var currentAnnotation: AnnotationItem?
    var cropRect: CGRect?
    var isCropping: Bool = false
    weak var delegate: AnnotationNSViewDelegate?
    
    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: NSSize {
        return image.size
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw image
        image.draw(in: bounds)
        
        // Draw completed annotations
        for annotation in annotations {
            drawAnnotation(annotation)
        }
        
        // Draw current annotation
        if let current = currentAnnotation {
            drawAnnotation(current)
        }
        
        // Draw crop overlay
        if isCropping, let rect = cropRect {
            drawCropOverlay(rect)
        }
    }
    
    private func drawCropOverlay(_ rect: CGRect) {
        // Dim outside crop area
        NSColor.black.withAlphaComponent(0.5).setFill()
        
        // Top
        NSBezierPath(rect: NSRect(x: 0, y: rect.maxY, width: bounds.width, height: bounds.height - rect.maxY)).fill()
        // Bottom
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.width, height: rect.minY)).fill()
        // Left
        NSBezierPath(rect: NSRect(x: 0, y: rect.minY, width: rect.minX, height: rect.height)).fill()
        // Right
        NSBezierPath(rect: NSRect(x: rect.maxX, y: rect.minY, width: bounds.width - rect.maxX, height: rect.height)).fill()
        
        // Crop border
        NSColor.white.setStroke()
        let borderPath = NSBezierPath(rect: rect)
        borderPath.lineWidth = 2
        let pattern: [CGFloat] = [6, 3]
        borderPath.setLineDash(pattern, count: 2, phase: 0)
        borderPath.stroke()
        
        // Corner handles
        let handleSize: CGFloat = 8
        NSColor.white.setFill()
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        for corner in corners {
            let handleRect = NSRect(x: corner.x - handleSize/2, y: corner.y - handleSize/2, width: handleSize, height: handleSize)
            NSBezierPath(ovalIn: handleRect).fill()
        }
    }
    
    private func drawAnnotation(_ annotation: AnnotationItem) {
        annotation.color.setStroke()
        annotation.color.setFill()
        
        switch annotation.tool {
        case .arrow:
            drawArrow(from: annotation.startPoint, to: annotation.endPoint, width: annotation.strokeWidth, color: annotation.color)
        case .rectangle:
            let rect = rectFrom(start: annotation.startPoint, end: annotation.endPoint)
            let path = NSBezierPath(rect: rect)
            path.lineWidth = annotation.strokeWidth
            path.stroke()
        case .filledRect:
            let rect = rectFrom(start: annotation.startPoint, end: annotation.endPoint)
            annotation.color.withAlphaComponent(0.3).setFill()
            NSBezierPath(rect: rect).fill()
            annotation.color.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = annotation.strokeWidth
            path.stroke()
        case .ellipse:
            let rect = rectFrom(start: annotation.startPoint, end: annotation.endPoint)
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = annotation.strokeWidth
            path.stroke()
        case .filledEllipse:
            let rect = rectFrom(start: annotation.startPoint, end: annotation.endPoint)
            annotation.color.withAlphaComponent(0.3).setFill()
            NSBezierPath(ovalIn: rect).fill()
            annotation.color.setStroke()
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = annotation.strokeWidth
            path.stroke()
        case .line:
            let path = NSBezierPath()
            path.move(to: annotation.startPoint)
            path.line(to: annotation.endPoint)
            path.lineWidth = annotation.strokeWidth
            path.stroke()
        case .pencil:
            drawPencilPath(annotation)
        case .highlight:
            let rect = rectFrom(start: annotation.startPoint, end: annotation.endPoint)
            annotation.color.withAlphaComponent(0.3).setFill()
            NSBezierPath(rect: rect).fill()
        case .blur, .redact:
            drawPixelatedBlur(annotation)
        case .spotlight:
            drawSpotlight(annotation)
        case .number:
            drawNumber(annotation)
        case .text:
            if let text = annotation.text {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: annotation.fontSize),
                    .foregroundColor: annotation.color
                ]
                text.draw(at: annotation.startPoint, withAttributes: attributes)
            }
        case .emoji:
            if let emoji = annotation.emoji {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: annotation.fontSize)
                ]
                let emojiSize = emoji.size(withAttributes: attributes)
                let drawPoint = NSPoint(
                    x: annotation.startPoint.x - emojiSize.width/2,
                    y: annotation.startPoint.y - emojiSize.height/2
                )
                emoji.draw(at: drawPoint, withAttributes: attributes)
            }
        case .crop:
            break
        }
    }
    
    private func drawNumber(_ annotation: AnnotationItem) {
        guard let number = annotation.number else { return }
        let size: CGFloat = 28
        let rect = NSRect(
            x: annotation.startPoint.x - size/2,
            y: annotation.startPoint.y - size/2,
            width: size,
            height: size
        )
        annotation.color.setFill()
        NSBezierPath(ovalIn: rect).fill()
        
        let text = "\(number)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let textPoint = NSPoint(
            x: annotation.startPoint.x - textSize.width/2,
            y: annotation.startPoint.y - textSize.height/2
        )
        text.draw(at: textPoint, withAttributes: attributes)
    }
    
    private func drawSpotlight(_ annotation: AnnotationItem) {
        let spotlightRect = rectFrom(start: annotation.startPoint, end: annotation.endPoint)
        
        NSColor.black.withAlphaComponent(0.6).setFill()
        
        // Top
        NSBezierPath(rect: NSRect(x: 0, y: spotlightRect.maxY, width: bounds.width, height: bounds.height - spotlightRect.maxY)).fill()
        // Bottom
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.width, height: spotlightRect.minY)).fill()
        // Left
        NSBezierPath(rect: NSRect(x: 0, y: spotlightRect.minY, width: spotlightRect.minX, height: spotlightRect.height)).fill()
        // Right
        NSBezierPath(rect: NSRect(x: spotlightRect.maxX, y: spotlightRect.minY, width: bounds.width - spotlightRect.maxX, height: spotlightRect.height)).fill()
        
        annotation.color.setStroke()
        let borderPath = NSBezierPath(rect: spotlightRect)
        borderPath.lineWidth = 2
        borderPath.stroke()
    }
    
    private func drawPencilPath(_ annotation: AnnotationItem) {
        guard annotation.pathPoints.count > 1 else { return }
        
        let path = NSBezierPath()
        path.move(to: annotation.pathPoints[0])
        
        for i in 1..<annotation.pathPoints.count {
            path.line(to: annotation.pathPoints[i])
        }
        
        path.lineWidth = annotation.strokeWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        annotation.color.setStroke()
        path.stroke()
    }
    
    private func drawPixelatedBlur(_ annotation: AnnotationItem) {
        let rect = rectFrom(start: annotation.startPoint, end: annotation.endPoint)
        guard rect.width > 0 && rect.height > 0 else { return }
        
        let pixelSize: CGFloat = annotation.tool == .redact ? 8 : 12
        
        for y in stride(from: rect.minY, to: rect.maxY, by: pixelSize) {
            for x in stride(from: rect.minX, to: rect.maxX, by: pixelSize) {
                let pixelRect = NSRect(x: x, y: y, width: pixelSize, height: pixelSize)
                
                if annotation.tool == .redact {
                    NSColor.black.setFill()
                } else {
                    let grayValue = CGFloat.random(in: 0.4...0.7)
                    NSColor(white: grayValue, alpha: 0.95).setFill()
                }
                NSBezierPath(rect: pixelRect).fill()
            }
        }
    }
    
    private func rectFrom(start: CGPoint, end: CGPoint) -> NSRect {
        return NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
    
    private func drawArrow(from start: CGPoint, to end: CGPoint, width: CGFloat, color: NSColor) {
        color.setStroke()
        
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
        
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 15 + width
        let arrowAngle: CGFloat = .pi / 6
        
        let point1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let point2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        
        color.setFill()
        let arrowPath = NSBezierPath()
        arrowPath.move(to: end)
        arrowPath.line(to: point1)
        arrowPath.line(to: point2)
        arrowPath.close()
        arrowPath.fill()
    }
    
    // MARK: - Mouse Events
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        delegate?.didStartAnnotation(at: point)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        delegate?.didUpdateAnnotation(to: point)
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        delegate?.didEndAnnotation(at: point)
        needsDisplay = true
    }
}

// MARK: - Annotation Editor View (for WindowGroup)
struct AnnotationEditorView: View {
    @EnvironmentObject var annotationState: AnnotationState
    
    var body: some View {
        Group {
            if let image = annotationState.currentImage {
                AnnotationEditorContentView(
                    image: image,
                    onSave: { editedImage in
                        saveImage(editedImage)
                    },
                    onCopy: { editedImage in
                        copyImage(editedImage)
                    }
                )
            } else {
                Text("No image to annotate")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    private func saveImage(_ image: NSImage) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "Annotated-\(Date().formatted(.dateTime.year().month().day().hour().minute().second()))"
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }
    }
    
    private func copyImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}
