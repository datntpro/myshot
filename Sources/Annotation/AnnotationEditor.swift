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

enum AnnotationTool: String, CaseIterable {
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case line = "Line"
    case pencil = "Pencil"
    case text = "Text"
    case highlight = "Highlight"
    case blur = "Blur"
    case number = "Number"
    case crop = "Crop"
    
    var icon: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .pencil: return "pencil"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .blur: return "checkerboard.rectangle"
        case .number: return "number.circle"
        case .crop: return "crop"
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
    var pathPoints: [CGPoint] = [] // For pencil/freehand drawing
}

// MARK: - Annotation Window
class AnnotationWindow: NSWindow {
    private var image: NSImage
    private var hostingView: NSHostingView<AnnotationEditorContentView>?
    
    init(image: NSImage) {
        self.image = image
        
        let screenSize = NSScreen.main?.frame.size ?? NSSize(width: 1200, height: 800)
        let maxWidth = min(image.size.width + 100, screenSize.width * 0.9)
        let maxHeight = min(image.size.height + 150, screenSize.height * 0.9)
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: maxWidth, height: maxHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Annotation Editor"
        self.center()
        
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
    @State private var numberCounter: Int = 1
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarView
            
            Divider()
            
            // Canvas
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    AnnotationCanvasView(
                        image: image,
                        annotations: $annotations,
                        currentAnnotation: $currentAnnotation,
                        selectedTool: selectedTool,
                        strokeColor: NSColor(strokeColor),
                        strokeWidth: strokeWidth,
                        numberCounter: $numberCounter
                    )
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var toolbarView: some View {
        HStack(spacing: 16) {
            // Tools
            HStack(spacing: 4) {
                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                    ToolButton(
                        tool: tool,
                        isSelected: selectedTool == tool,
                        action: { selectedTool = tool }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Divider()
                .frame(height: 24)
            
            // Color picker
            ColorPicker("", selection: $strokeColor)
                .labelsHidden()
                .frame(width: 40)
            
            // Stroke width
            HStack(spacing: 4) {
                Text("Width:")
                    .font(.caption)
                Slider(value: $strokeWidth, in: 1...10, step: 1)
                    .frame(width: 80)
                Text("\(Int(strokeWidth))")
                    .font(.caption)
                    .frame(width: 20)
            }
            
            Spacer()
            
            // Undo
            Button(action: {
                if !annotations.isEmpty {
                    annotations.removeLast()
                }
            }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(annotations.isEmpty)
            
            // Clear all
            Button(action: {
                annotations.removeAll()
                numberCounter = 1
            }) {
                Image(systemName: "trash")
            }
            .disabled(annotations.isEmpty)
            
            Divider()
                .frame(height: 24)
            
            // Save/Copy actions
            Button("Copy") {
                let renderedImage = renderAnnotatedImage()
                onCopy(renderedImage)
            }
            
            Button("Save") {
                let renderedImage = renderAnnotatedImage()
                onSave(renderedImage)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
            drawArrow(from: annotation.startPoint, to: annotation.endPoint, width: annotation.strokeWidth)
        case .rectangle:
            let rect = NSRect(
                x: min(annotation.startPoint.x, annotation.endPoint.x),
                y: min(annotation.startPoint.y, annotation.endPoint.y),
                width: abs(annotation.endPoint.x - annotation.startPoint.x),
                height: abs(annotation.endPoint.y - annotation.startPoint.y)
            )
            let path = NSBezierPath(rect: rect)
            path.lineWidth = annotation.strokeWidth
            path.stroke()
        case .ellipse:
            let rect = NSRect(
                x: min(annotation.startPoint.x, annotation.endPoint.x),
                y: min(annotation.startPoint.y, annotation.endPoint.y),
                width: abs(annotation.endPoint.x - annotation.startPoint.x),
                height: abs(annotation.endPoint.y - annotation.startPoint.y)
            )
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
            let rect = NSRect(
                x: min(annotation.startPoint.x, annotation.endPoint.x),
                y: min(annotation.startPoint.y, annotation.endPoint.y),
                width: abs(annotation.endPoint.x - annotation.startPoint.x),
                height: abs(annotation.endPoint.y - annotation.startPoint.y)
            )
            annotation.color.withAlphaComponent(0.3).setFill()
            NSBezierPath(rect: rect).fill()
        case .text:
            if let text = annotation.text {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 16),
                    .foregroundColor: annotation.color
                ]
                text.draw(at: annotation.startPoint, withAttributes: attributes)
            }
        case .number:
            if let number = annotation.number {
                let size: CGFloat = 24
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
                    .font: NSFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: NSColor.white
                ]
                let textSize = text.size(withAttributes: attributes)
                let textPoint = NSPoint(
                    x: annotation.startPoint.x - textSize.width/2,
                    y: annotation.startPoint.y - textSize.height/2
                )
                text.draw(at: textPoint, withAttributes: attributes)
            }
        case .blur:
            // Pixelate blur
            let rect = NSRect(
                x: min(annotation.startPoint.x, annotation.endPoint.x),
                y: min(annotation.startPoint.y, annotation.endPoint.y),
                width: abs(annotation.endPoint.x - annotation.startPoint.x),
                height: abs(annotation.endPoint.y - annotation.startPoint.y)
            )
            let pixelSize: CGFloat = 10
            for y in stride(from: rect.minY, to: rect.maxY, by: pixelSize) {
                for x in stride(from: rect.minX, to: rect.maxX, by: pixelSize) {
                    let pixelRect = NSRect(x: x, y: y, width: pixelSize, height: pixelSize)
                    let grayValue = CGFloat.random(in: 0.4...0.7)
                    NSColor(white: grayValue, alpha: 0.95).setFill()
                    NSBezierPath(rect: pixelRect).fill()
                }
            }
        case .crop:
            break
        }
    }
    
    private func drawArrow(from start: CGPoint, to end: CGPoint, width: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = width
        path.stroke()
        
        // Arrow head
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 15
        let arrowAngle: CGFloat = .pi / 6
        
        let point1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let point2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        
        let arrowPath = NSBezierPath()
        arrowPath.move(to: end)
        arrowPath.line(to: point1)
        arrowPath.move(to: end)
        arrowPath.line(to: point2)
        arrowPath.lineWidth = width
        arrowPath.stroke()
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
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.accentColor : Color.clear)
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(tool.rawValue)
    }
}

// MARK: - Annotation Canvas View
struct AnnotationCanvasView: NSViewRepresentable {
    let image: NSImage
    @Binding var annotations: [AnnotationItem]
    @Binding var currentAnnotation: AnnotationItem?
    let selectedTool: AnnotationTool
    let strokeColor: NSColor
    let strokeWidth: CGFloat
    @Binding var numberCounter: Int
    
    func makeNSView(context: Context) -> AnnotationNSView {
        let view = AnnotationNSView(image: image)
        view.delegate = context.coordinator
        return view
    }
    
    func updateNSView(_ nsView: AnnotationNSView, context: Context) {
        nsView.annotations = annotations
        nsView.currentAnnotation = currentAnnotation
        nsView.needsDisplay = true
        context.coordinator.selectedTool = selectedTool
        context.coordinator.strokeColor = strokeColor
        context.coordinator.strokeWidth = strokeWidth
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, AnnotationNSViewDelegate {
        var parent: AnnotationCanvasView
        var selectedTool: AnnotationTool = .arrow
        var strokeColor: NSColor = .red
        var strokeWidth: CGFloat = 3
        
        init(_ parent: AnnotationCanvasView) {
            self.parent = parent
        }
        
        func didStartAnnotation(at point: CGPoint) {
            if selectedTool == .number {
                let annotation = AnnotationItem(
                    tool: selectedTool,
                    startPoint: point,
                    endPoint: point,
                    color: strokeColor,
                    strokeWidth: strokeWidth,
                    number: parent.numberCounter
                )
                parent.annotations.append(annotation)
                parent.numberCounter += 1
            } else if selectedTool == .pencil {
                var annotation = AnnotationItem(
                    tool: selectedTool,
                    startPoint: point,
                    endPoint: point,
                    color: strokeColor,
                    strokeWidth: strokeWidth
                )
                annotation.pathPoints = [point]
                parent.currentAnnotation = annotation
            } else {
                parent.currentAnnotation = AnnotationItem(
                    tool: selectedTool,
                    startPoint: point,
                    endPoint: point,
                    color: strokeColor,
                    strokeWidth: strokeWidth
                )
            }
        }
        
        func didUpdateAnnotation(to point: CGPoint) {
            if parent.currentAnnotation?.tool == .pencil {
                parent.currentAnnotation?.pathPoints.append(point)
            }
            parent.currentAnnotation?.endPoint = point
        }
        
        func didEndAnnotation(at point: CGPoint) {
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
        case .ellipse:
            let rect = rectFrom(start: annotation.startPoint, end: annotation.endPoint)
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
        case .blur:
            drawPixelatedBlur(annotation)
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
        case .text, .crop:
            break
        }
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
        
        // Draw a pixelated/mosaic pattern
        let pixelSize: CGFloat = 10
        
        for y in stride(from: rect.minY, to: rect.maxY, by: pixelSize) {
            for x in stride(from: rect.minX, to: rect.maxX, by: pixelSize) {
                let pixelRect = NSRect(x: x, y: y, width: pixelSize, height: pixelSize)
                
                // Randomly vary the gray color for mosaic effect
                let grayValue = CGFloat.random(in: 0.4...0.7)
                NSColor(white: grayValue, alpha: 0.95).setFill()
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
