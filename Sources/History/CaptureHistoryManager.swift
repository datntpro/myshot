import Foundation
import SwiftUI

class CaptureHistoryManager: ObservableObject {
    static let shared = CaptureHistoryManager()
    
    @Published var captures: [CaptureItem] = []
    
    private let maxHistoryItems = 50
    private let historyDirectory: URL
    
    private init() {
        // Create history directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        historyDirectory = appSupport.appendingPathComponent("MyShot/History", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        
        loadHistory()
    }
    
    func addCapture(image: NSImage) {
        let id = UUID()
        let filename = "\(id.uuidString).png"
        let fileURL = historyDirectory.appendingPathComponent(filename)
        
        // Convert image to PNG data on main thread (NSImage is not thread-safe)
        var pngData: Data?
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData) {
            pngData = bitmap.representation(using: .png, properties: [:])
        }
        
        let capture = CaptureItem(
            id: id,
            date: Date(),
            filename: filename,
            fileURL: fileURL
        )
        
        // Update UI on main thread since @Published requires main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.captures.insert(capture, at: 0)
            
            // Trim old captures
            if self.captures.count > self.maxHistoryItems {
                let removed = self.captures.removeLast()
                // Delete old file in background
                DispatchQueue.global(qos: .background).async {
                    try? FileManager.default.removeItem(at: removed.fileURL)
                }
            }
            
            self.saveHistoryMetadata()
        }
        
        // Save PNG data to disk in background (writing data is thread-safe)
        if let data = pngData {
            DispatchQueue.global(qos: .userInitiated).async {
                try? data.write(to: fileURL)
            }
        }
    }
    
    func deleteCapture(_ capture: CaptureItem) {
        try? FileManager.default.removeItem(at: capture.fileURL)
        captures.removeAll { $0.id == capture.id }
        saveHistoryMetadata()
    }
    
    func clearHistory() {
        for capture in captures {
            try? FileManager.default.removeItem(at: capture.fileURL)
        }
        captures.removeAll()
        saveHistoryMetadata()
    }
    
    func loadImage(for capture: CaptureItem) -> NSImage? {
        return NSImage(contentsOf: capture.fileURL)
    }
    
    private func loadHistory() {
        let metadataURL = historyDirectory.appendingPathComponent("metadata.json")
        
        guard let data = try? Data(contentsOf: metadataURL),
              let items = try? JSONDecoder().decode([CaptureItem].self, from: data) else {
            return
        }
        
        // Filter out items whose files no longer exist
        captures = items.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }
    
    private func saveHistoryMetadata() {
        let metadataURL = historyDirectory.appendingPathComponent("metadata.json")
        
        if let data = try? JSONEncoder().encode(captures) {
            try? data.write(to: metadataURL)
        }
    }
}

struct CaptureItem: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let filename: String
    let fileURL: URL
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - History View
struct HistoryView: View {
    @EnvironmentObject var historyManager: CaptureHistoryManager
    @State private var selectedCapture: CaptureItem?
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationSplitView {
            List(historyManager.captures, selection: $selectedCapture) { capture in
                HStack {
                    if let image = historyManager.loadImage(for: capture) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    VStack(alignment: .leading) {
                        Text(capture.formattedDate)
                            .font(.subheadline)
                        Text(capture.filename)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .tag(capture)
                .contextMenu {
                    Button("Copy") {
                        copyCapture(capture)
                    }
                    Button("Open in Finder") {
                        NSWorkspace.shared.selectFile(capture.fileURL.path, inFileViewerRootedAtPath: "")
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        historyManager.deleteCapture(capture)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        Image(systemName: "trash")
                    }
                    .disabled(historyManager.captures.isEmpty)
                    .help("Clear History")
                }
            }
            .alert("Clear History?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive) {
                    historyManager.clearHistory()
                }
            } message: {
                Text("This will delete all captured screenshots from history. This action cannot be undone.")
            }
        } detail: {
            if let capture = selectedCapture,
               let image = historyManager.loadImage(for: capture) {
                DetailView(capture: capture, image: image)
            } else {
                Text("Select a capture to preview")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    private func copyCapture(_ capture: CaptureItem) {
        if let image = historyManager.loadImage(for: capture) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
    }
}

struct DetailView: View {
    let capture: CaptureItem
    let image: NSImage
    
    var body: some View {
        VStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding()
            
            HStack {
                Text(capture.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([image])
                }
                
                Button("Open in Finder") {
                    NSWorkspace.shared.selectFile(capture.fileURL.path, inFileViewerRootedAtPath: "")
                }
                
                Button("Annotate") {
                    AnnotationState.shared.setImage(image)
                    let window = AnnotationWindow(image: image)
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .padding()
        }
    }
}
