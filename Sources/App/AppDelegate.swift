import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayWindow: OverlayWindow?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var annotationWindow: AnnotationWindow?
    private var globalMonitor: Any?
    private var hasShownOnboarding = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 MyShot launched")
        setupStatusBar()
        setupGlobalHotkeys()
        
        // Show onboarding once on first launch
        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunched {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            showPermissionOnboarding()
        }
        
        NSApp.setActivationPolicy(.accessory)
        print("✅ Setup complete")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // MARK: - Permissions
    private func showPermissionOnboarding() {
        let onboardingView = PermissionOnboardingView(onClose: { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        })
        
        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MyShot - Setup"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 500, height: 420))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }
    
    // MARK: - Global Hotkeys
    private func setupGlobalHotkeys() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleGlobalKeyEvent(event)
        }
        print("⌨️ Global hotkeys: Ctrl+Shift+3/4/5/6")
    }
    
    private func handleGlobalKeyEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.control, .shift, .command, .option])
        guard modifiers == [.control, .shift] else { return }
        
        switch event.keyCode {
        case 20: DispatchQueue.main.async { [weak self] in self?.captureFullscreen() }
        case 21: DispatchQueue.main.async { [weak self] in self?.captureArea() }
        case 23: DispatchQueue.main.async { [weak self] in self?.captureWindow() }
        case 22: DispatchQueue.main.async { [weak self] in self?.captureOCR() }
        default: break
        }
    }
    
    // MARK: - Status Bar
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "MyShot")
        }
        setupMenu()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // Quick capture actions with visible shortcuts
        let areaItem = NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: "4")
        areaItem.keyEquivalentModifierMask = [.control, .shift]
        menu.addItem(areaItem)
        
        let fullscreenItem = NSMenuItem(title: "Capture Fullscreen", action: #selector(captureFullscreen), keyEquivalent: "3")
        fullscreenItem.keyEquivalentModifierMask = [.control, .shift]
        menu.addItem(fullscreenItem)
        
        let windowItem = NSMenuItem(title: "Capture Window", action: #selector(captureWindow), keyEquivalent: "5")
        windowItem.keyEquivalentModifierMask = [.control, .shift]
        menu.addItem(windowItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let ocrItem = NSMenuItem(title: "Capture Text (OCR)", action: #selector(captureOCR), keyEquivalent: "6")
        ocrItem.keyEquivalentModifierMask = [.control, .shift]
        menu.addItem(ocrItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Recording
        let recordMenu = NSMenu()
        recordMenu.addItem(NSMenuItem(title: "Record Video", action: #selector(recordVideo), keyEquivalent: ""))
        recordMenu.addItem(NSMenuItem(title: "Record GIF", action: #selector(recordGIF), keyEquivalent: ""))
        let recordItem = NSMenuItem(title: "Screen Recording", action: nil, keyEquivalent: "")
        recordItem.submenu = recordMenu
        menu.addItem(recordItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Capture History", action: #selector(openHistory), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Permission Setup...", action: #selector(showPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit MyShot", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc private func showPermissions() {
        showPermissionOnboarding()
    }
    
    // MARK: - Capture Actions (No permission check - just try capture)
    @objc func captureArea() {
        print("📷 Capture Area")
        ScreenCaptureManager.shared.startAreaSelection { [weak self] image in
            if let image = image { 
                self?.handleCapturedImage(image) 
            } else {
                print("⚠️ Capture failed - may need Screen Recording permission")
            }
        }
    }
    
    @objc func captureFullscreen() {
        print("📷 Capture Fullscreen")
        ScreenCaptureManager.shared.captureFullscreen { [weak self] image in
            if let image = image { 
                self?.handleCapturedImage(image) 
            } else {
                print("⚠️ Capture failed - may need Screen Recording permission")
            }
        }
    }
    
    @objc func captureWindow() {
        print("📷 Capture Window")
        ScreenCaptureManager.shared.captureWindow { [weak self] image in
            if let image = image { 
                self?.handleCapturedImage(image) 
            } else {
                print("⚠️ Capture failed - may need Screen Recording permission")
            }
        }
    }
    
    @objc private func captureScrolling() {
        ScrollingCaptureManager.shared.startScrollingCapture { [weak self] image in
            if let image = image { self?.handleCapturedImage(image) }
        }
    }
    
    @objc func captureOCR() {
        print("📷 Capture OCR")
        ScreenCaptureManager.shared.startAreaSelection { [weak self] image in
            guard let image = image else { return }
            OCRManager.shared.recognizeText(from: image) { text in
                if let text = text, !text.isEmpty {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Text Copied!"
                        alert.informativeText = String(text.prefix(200))
                        alert.runModal()
                    }
                }
            }
        }
    }
    
    @objc private func recordVideo() {
        ScreenRecordingManager.shared.startRecording(asGif: false)
    }
    
    @objc private func recordGIF() {
        ScreenRecordingManager.shared.startRecording(asGif: true)
    }
    
    @objc private func openHistory() {
        if let window = historyWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let hostingController = NSHostingController(rootView: HistoryView().environmentObject(CaptureHistoryManager.shared))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Capture History"
        window.setContentSize(NSSize(width: 700, height: 500))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        historyWindow = window
    }
    
    private func handleCapturedImage(_ image: NSImage) {
        print("✅ Captured: \(Int(image.size.width))x\(Int(image.size.height))")
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        
        CaptureHistoryManager.shared.addCapture(image: image)
        
        if SettingsManager.shared.playCaptureSound {
            NSSound(named: "Tink")?.play()
        }
        
        if SettingsManager.shared.showOverlay {
            DispatchQueue.main.async { [weak self] in
                self?.showOverlay(with: image)
            }
        }
    }
    
    private func showOverlay(with image: NSImage) {
        if let existing = overlayWindow {
            existing.orderOut(nil)
            overlayWindow = nil
        }
        let newOverlay = OverlayWindow(image: image)
        overlayWindow = newOverlay
        newOverlay.show()
    }
    
    @objc private func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 480))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Permission Onboarding View
struct PermissionOnboardingView: View {
    let onClose: () -> Void
    @State private var screenRecordingStatus = "Checking..."
    @State private var accessibilityStatus = "Checking..."
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 50))
                .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            
            Text("MyShot Setup")
                .font(.title)
                .bold()
            
            Text("Grant permissions to enable all features")
                .foregroundColor(.secondary)
            
            VStack(spacing: 16) {
                PermissionCard(
                    icon: "rectangle.dashed.badge.record",
                    iconColor: .red,
                    title: "Screen Recording",
                    description: "Required to capture screenshots and record screen",
                    buttonTitle: "Open Screen Recording Settings",
                    action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
                
                PermissionCard(
                    icon: "keyboard",
                    iconColor: .blue,
                    title: "Accessibility",
                    description: "Required for global keyboard shortcuts",
                    buttonTitle: "Open Accessibility Settings",
                    action: {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                        AXIsProcessTrustedWithOptions(options as CFDictionary)
                    }
                )
            }
            
            Divider()
            
            VStack(spacing: 8) {
                Text("After enabling permissions:")
                    .font(.headline)
                Text("1. Toggle ON for MyShot in both settings")
                Text("2. Restart MyShot if needed")
                Text("3. Use menu or Ctrl+Shift+3/4/5/6")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            Button("Done") {
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(25)
        .frame(width: 500, height: 420)
    }
}

struct PermissionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let buttonTitle: String
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(iconColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(buttonTitle) {
                action()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}
