import Foundation
import SwiftUI

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @AppStorage("saveLocation") var saveLocation: String = NSHomeDirectory() + "/Desktop"
    @AppStorage("autoSave") var autoSave: Bool = false
    @AppStorage("useCustomWallpaper") var useCustomWallpaper: Bool = false
    @AppStorage("wallpaperType") var wallpaperType: String = "gradient"  // solid, gradient, image
    @AppStorage("wallpaperColorHex") var wallpaperColorHex: String = "#667eea"
    @AppStorage("wallpaperColor2Hex") var wallpaperColor2Hex: String = "#764ba2"
    @AppStorage("wallpaperGradientPreset") var wallpaperGradientPreset: String = "purple"
    @AppStorage("wallpaperImagePath") var wallpaperImagePath: String = ""
    @AppStorage("wallpaperPadding") var wallpaperPadding: Double = 40
    @AppStorage("windowCornerRadius") var windowCornerRadius: Double = 12
    @AppStorage("playCaptureSound") var playCaptureSound: Bool = true
    @AppStorage("showCursor") var showCursor: Bool = false
    @AppStorage("showOverlay") var showOverlay: Bool = true
    @AppStorage("overlayDuration") var overlayDuration: Double = 5.0
    @AppStorage("videoQuality") var videoQuality: String = "high"
    @AppStorage("videoFPS") var videoFPS: Int = 60
    
    // Auto-Redact Settings
    @AppStorage("autoRedactEnabled") var autoRedactEnabled: Bool = false
    @AppStorage("redactCreditCards") var redactCreditCards: Bool = true
    @AppStorage("redactAPIKeys") var redactAPIKeys: Bool = true
    @AppStorage("redactPasswords") var redactPasswords: Bool = true
    @AppStorage("redactionStyle") var redactionStyle: String = "blur"
    @AppStorage("showRedactPreview") var showRedactPreview: Bool = true
    
    var videoBitrate: Int {
        switch videoQuality {
        case "low": return 5_000_000
        case "medium": return 10_000_000
        case "high": return 15_000_000
        case "ultra": return 25_000_000
        default: return 15_000_000
        }
    }
    
    var wallpaperColor: NSColor? {
        get { NSColor(hex: wallpaperColorHex) }
        set { if let c = newValue { wallpaperColorHex = c.hexString } }
    }
    
    var wallpaperColor2: NSColor? {
        get { NSColor(hex: wallpaperColor2Hex) }
        set { if let c = newValue { wallpaperColor2Hex = c.hexString } }
    }
    
    // Gradient presets
    static let gradientPresets: [(name: String, color1: String, color2: String)] = [
        ("Purple", "#667eea", "#764ba2"),
        ("Ocean", "#2193b0", "#6dd5ed"),
        ("Sunset", "#f093fb", "#f5576c"),
        ("Forest", "#11998e", "#38ef7d"),
        ("Fire", "#f12711", "#f5af19"),
        ("Night", "#0f0c29", "#302b63"),
        ("Pink", "#ee9ca7", "#ffdde1"),
        ("Midnight", "#232526", "#414345"),
    ]
    
    private init() {}
}

extension NSColor {
    convenience init?(hex: String) {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&rgb) else { return nil }
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
    
    var hexString: String {
        guard let c = usingColorSpace(.deviceRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView().tabItem { Label("General", systemImage: "gear") }
            AutoRedactSettingsView().tabItem { Label("Auto-Redact", systemImage: "eye.slash") }
            QualitySettingsView().tabItem { Label("Quality", systemImage: "sparkles") }
            WallpaperSettingsView().tabItem { Label("Wallpaper", systemImage: "photo.artframe") }
        }
        .frame(width: 520, height: 520)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Play capture sound", isOn: $settings.playCaptureSound)
                Toggle("Show cursor in screenshots", isOn: $settings.showCursor)
            }
            Section("Quick Access Overlay") {
                Toggle("Show overlay after capture", isOn: $settings.showOverlay)
                if settings.showOverlay {
                    HStack {
                        Text("Auto-hide")
                        Slider(value: $settings.overlayDuration, in: 2...10, step: 1)
                        Text("\(Int(settings.overlayDuration))s").frame(width: 30)
                    }
                }
            }
            Section("Save Location") {
                HStack {
                    Text(settings.saveLocation).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.saveLocation = url.path
                        }
                    }
                }
            }
        }.formStyle(.grouped).padding()
    }
}

struct QualitySettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        Form {
            Section("Video Recording") {
                Picker("Quality", selection: $settings.videoQuality) {
                    Text("Low (5 Mbps)").tag("low")
                    Text("Medium (10 Mbps)").tag("medium")
                    Text("High (15 Mbps)").tag("high")
                    Text("Ultra (25 Mbps)").tag("ultra")
                }.pickerStyle(.segmented)
                
                Picker("Frame Rate", selection: $settings.videoFPS) {
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                }.pickerStyle(.segmented)
            }
        }.formStyle(.grouped).padding()
    }
}

struct WallpaperSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var color1: Color = .purple
    @State private var color2: Color = .blue
    
    var body: some View {
        Form {
            Section("Screenshot Background") {
                Toggle("Enable custom wallpaper", isOn: $settings.useCustomWallpaper)
                
                if settings.useCustomWallpaper {
                    Picker("Type", selection: $settings.wallpaperType) {
                        Text("Solid Color").tag("solid")
                        Text("Gradient").tag("gradient")
                        Text("Custom Image").tag("image")
                    }.pickerStyle(.segmented)
                    
                    if settings.wallpaperType == "solid" {
                        ColorPicker("Background Color", selection: $color1)
                            .onChange(of: color1) { newValue in
                                settings.wallpaperColorHex = newValue.hex
                            }
                    }
                    
                    if settings.wallpaperType == "gradient" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Presets").font(.caption).foregroundColor(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 8) {
                                ForEach(SettingsManager.gradientPresets, id: \.name) { preset in
                                    Button(action: {
                                        settings.wallpaperColorHex = preset.color1
                                        settings.wallpaperColor2Hex = preset.color2
                                        color1 = Color(hex: preset.color1) ?? .purple
                                        color2 = Color(hex: preset.color2) ?? .blue
                                    }) {
                                        LinearGradient(colors: [Color(hex: preset.color1) ?? .purple, Color(hex: preset.color2) ?? .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                                            .frame(width: 50, height: 35)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(settings.wallpaperColorHex == preset.color1 ? Color.white : Color.clear, lineWidth: 2)
                                            )
                                    }.buttonStyle(.plain)
                                }
                            }
                            
                            HStack {
                                ColorPicker("Color 1", selection: $color1)
                                    .onChange(of: color1) { newValue in settings.wallpaperColorHex = newValue.hex }
                                ColorPicker("Color 2", selection: $color2)
                                    .onChange(of: color2) { newValue in settings.wallpaperColor2Hex = newValue.hex }
                            }
                        }
                    }
                    
                    if settings.wallpaperType == "image" {
                        HStack {
                            Text(settings.wallpaperImagePath.isEmpty ? "No image selected" : URL(fileURLWithPath: settings.wallpaperImagePath).lastPathComponent)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Choose...") {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.image]
                                if panel.runModal() == .OK, let url = panel.url {
                                    settings.wallpaperImagePath = url.path
                                }
                            }
                        }
                    }
                }
            }
            
            if settings.useCustomWallpaper {
                Section("Style") {
                    HStack {
                        Text("Padding")
                        Slider(value: $settings.wallpaperPadding, in: 10...100, step: 5)
                        Text("\(Int(settings.wallpaperPadding))px").frame(width: 45)
                    }
                    HStack {
                        Text("Corner Radius")
                        Slider(value: $settings.windowCornerRadius, in: 0...30, step: 2)
                        Text("\(Int(settings.windowCornerRadius))px").frame(width: 45)
                    }
                }
                
                Section("Preview") {
                    ZStack {
                        if settings.wallpaperType == "gradient" {
                            LinearGradient(colors: [color1, color2], startPoint: .topLeading, endPoint: .bottomTrailing)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else if settings.wallpaperType == "image", !settings.wallpaperImagePath.isEmpty,
                                  let img = NSImage(contentsOfFile: settings.wallpaperImagePath) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            RoundedRectangle(cornerRadius: 8).fill(color1)
                        }
                        
                        RoundedRectangle(cornerRadius: settings.windowCornerRadius / 2)
                            .fill(.white).padding(settings.wallpaperPadding / 4)
                            .overlay(
                                Image(systemName: "photo").font(.title).foregroundColor(.gray)
                            )
                    }.frame(height: 100)
                }
            }
        }
        .formStyle(.grouped).padding()
        .onAppear {
            color1 = Color(hex: settings.wallpaperColorHex) ?? .purple
            color2 = Color(hex: settings.wallpaperColor2Hex) ?? .blue
        }
    }
}

// MARK: - Auto-Redact Settings View
struct AutoRedactSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Auto-Redact", isOn: $settings.autoRedactEnabled)
                    .font(.headline)
                
                if settings.autoRedactEnabled {
                    Text("Automatically detect and blur sensitive information in screenshots")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if settings.autoRedactEnabled {
                Section("Detection Types") {
                    Toggle(isOn: $settings.redactCreditCards) {
                        Label("Credit Card Numbers", systemImage: "creditcard")
                    }
                    Toggle(isOn: $settings.redactAPIKeys) {
                        Label("API Keys & Tokens", systemImage: "key")
                    }
                    Toggle(isOn: $settings.redactPasswords) {
                        Label("Passwords", systemImage: "lock")
                    }
                }
                
                Section("Redaction Style") {
                    Picker("Style", selection: $settings.redactionStyle) {
                        Label("Blur", systemImage: "drop.halffull").tag("blur")
                        Label("Pixelate", systemImage: "square.grid.3x3").tag("pixelate")
                        Label("Black Box", systemImage: "rectangle.fill").tag("blackBox")
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Behavior") {
                    Toggle("Show preview before redacting", isOn: $settings.showRedactPreview)
                    
                    if settings.showRedactPreview {
                        Text("Review detected items and choose which to redact")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Automatically redact without preview (faster)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&rgb) else { return nil }
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
    
    var hex: String {
        guard let c = NSColor(self).cgColor.components, c.count >= 3 else { return "#000000" }
        return String(format: "#%02X%02X%02X", Int(c[0] * 255), Int(c[1] * 255), Int(c[2] * 255))
    }
}
