import Cocoa
import SwiftUI

// MARK: - Redact Preview Window
class RedactPreviewWindow: NSWindow {
    private var originalImage: NSImage
    private var matches: [SensitiveDataMatch]
    private var onComplete: ((NSImage?) -> Void)?
    private var hostingView: NSHostingView<RedactPreviewContentView>?
    
    init(image: NSImage, matches: [SensitiveDataMatch], onComplete: @escaping (NSImage?) -> Void) {
        self.originalImage = image
        self.matches = matches
        self.onComplete = onComplete
        
        print("🖼️ RedactPreviewWindow init:")
        print("   Image size: \(image.size)")
        print("   Matches count: \(matches.count)")
        
        // Calculate window size based on image aspect ratio
        let maxWidth: CGFloat = 900
        let maxHeight: CGFloat = 700
        let aspectRatio = image.size.width / image.size.height
        
        var windowWidth = min(image.size.width, maxWidth)
        var windowHeight = windowWidth / aspectRatio
        
        if windowHeight > maxHeight {
            windowHeight = maxHeight
            windowWidth = windowHeight * aspectRatio
        }
        
        // Add space for toolbar and list
        let totalWidth = windowWidth + 280 // Side panel
        let totalHeight = windowHeight + 120 // Toolbar + bottom bar
        
        let frame = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
        
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Auto-Redact Preview"
        self.center()
        self.isReleasedWhenClosed = false
        
        setupContent()
    }
    
    private func setupContent() {
        let contentView = RedactPreviewContentView(
            image: originalImage,
            matches: matches,
            onCancel: { [weak self] in
                self?.onComplete?(nil)
                self?.close()
            },
            onApply: { [weak self] selectedMatches, style in
                guard let self = self else { return }
                let redactedImage = AutoRedactManager.shared.applyRedaction(
                    to: self.originalImage,
                    matches: selectedMatches,
                    style: style
                )
                self.onComplete?(redactedImage)
                self.close()
            }
        )
        
        hostingView = NSHostingView(rootView: contentView)
        self.contentView = hostingView
    }
    
    func show() {
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Preview Content View
struct RedactPreviewContentView: View {
    let image: NSImage
    @State private var matches: [SensitiveDataMatch]
    let onCancel: () -> Void
    let onApply: ([SensitiveDataMatch], RedactionStyle) -> Void
    
    @State private var selectedStyle: RedactionStyle = .blur
    @State private var hoveredMatchId: UUID?
    
    init(image: NSImage, matches: [SensitiveDataMatch], onCancel: @escaping () -> Void, onApply: @escaping ([SensitiveDataMatch], RedactionStyle) -> Void) {
        self.image = image
        self._matches = State(initialValue: matches)
        self.onCancel = onCancel
        self.onApply = onApply
        
        // Set default style from settings
        let styleString = SettingsManager.shared.redactionStyle
        self._selectedStyle = State(initialValue: RedactionStyle(rawValue: styleString) ?? .blur)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Review Detected Sensitive Data")
                    .font(.headline)
                
                Spacer()
                
                // Style picker
                Picker("Style", selection: $selectedStyle) {
                    ForEach(RedactionStyle.allCases, id: \.self) { style in
                        Label(style.rawValue, systemImage: style.icon).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Main content
            HStack(spacing: 0) {
                // Image preview with overlays
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay(
                            GeometryReader { geometry in
                                ForEach(matches) { match in
                                    if match.shouldRedact {
                                        MatchOverlay(
                                            match: match,
                                            imageSize: image.size,
                                            viewSize: geometry.size,
                                            isHovered: hoveredMatchId == match.id
                                        )
                                    }
                                }
                            }
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.1))
                
                Divider()
                
                // Side panel with match list
                VStack(alignment: .leading, spacing: 0) {
                    Text("Detected Items (\(matches.filter { $0.shouldRedact }.count)/\(matches.count))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    
                    Divider()
                    
                    if matches.isEmpty {
                        VStack {
                            Spacer()
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 40))
                                .foregroundColor(.green)
                            Text("No sensitive data detected")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                                    MatchRow(
                                        match: binding(for: index),
                                        isHovered: hoveredMatchId == match.id,
                                        onHover: { isHovered in
                                            hoveredMatchId = isHovered ? match.id : nil
                                        }
                                    )
                                    Divider()
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Quick actions
                    HStack {
                        Button("Select All") {
                            for i in matches.indices {
                                matches[i].shouldRedact = true
                            }
                        }
                        .buttonStyle(.borderless)
                        
                        Button("Deselect All") {
                            for i in matches.indices {
                                matches[i].shouldRedact = false
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(8)
                }
                .frame(width: 280)
                .background(Color(NSColor.controlBackgroundColor))
            }
            
            Divider()
            
            // Bottom buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Text("\(matches.filter { $0.shouldRedact }.count) items will be redacted")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                Spacer()
                
                Button("Apply Redaction") {
                    onApply(matches, selectedStyle)
                }
                .buttonStyle(.borderedProminent)
                .disabled(matches.filter { $0.shouldRedact }.isEmpty)
                .keyboardShortcut(.return)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    private func binding(for index: Int) -> Binding<SensitiveDataMatch> {
        Binding(
            get: { matches[index] },
            set: { matches[index] = $0 }
        )
    }
}

// MARK: - Match Overlay (on image)
struct MatchOverlay: View {
    let match: SensitiveDataMatch
    let imageSize: NSSize
    let viewSize: CGSize
    let isHovered: Bool
    
    var body: some View {
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let offsetX = (viewSize.width - scaledWidth) / 2
        let offsetY = (viewSize.height - scaledHeight) / 2
        
        let rect = CGRect(
            x: offsetX + match.boundingBox.origin.x * scale,
            y: offsetY + (imageSize.height - match.boundingBox.origin.y - match.boundingBox.height) * scale,
            width: match.boundingBox.width * scale,
            height: match.boundingBox.height * scale
        )
        
        RoundedRectangle(cornerRadius: 4)
            .stroke(color(for: match.type), lineWidth: isHovered ? 3 : 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color(for: match.type).opacity(isHovered ? 0.3 : 0.15))
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
    
    private func color(for type: SensitiveDataType) -> Color {
        switch type {
        case .creditCard: return .orange
        case .apiKey: return .red
        case .password: return .purple
        }
    }
}

// MARK: - Match Row (in list)
struct MatchRow: View {
    @Binding var match: SensitiveDataMatch
    let isHovered: Bool
    let onHover: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $match.shouldRedact)
                .labelsHidden()
            
            Image(systemName: match.type.icon)
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(match.type.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(match.maskedText)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        .onHover(perform: onHover)
    }
    
    private var iconColor: Color {
        switch match.type {
        case .creditCard: return .orange
        case .apiKey: return .red
        case .password: return .purple
        }
    }
}
