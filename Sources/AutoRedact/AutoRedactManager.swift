import Foundation
import Cocoa

// MARK: - Redaction Style
enum RedactionStyle: String, CaseIterable {
    case blur = "Blur"
    case pixelate = "Pixelate"
    case blackBox = "Black Box"
    
    var icon: String {
        switch self {
        case .blur: return "drop.halffull"
        case .pixelate: return "square.grid.3x3"
        case .blackBox: return "rectangle.fill"
        }
    }
}

// MARK: - Auto Redact Manager
class AutoRedactManager {
    static let shared = AutoRedactManager()
    
    private init() {}
    
    private let detector = SensitiveDataDetector.shared
    
    // MARK: - Detection
    
    /// Detect sensitive data in an image
    func detectSensitiveData(in image: NSImage, completion: @escaping ([SensitiveDataMatch]) -> Void) {
        detector.detectInImage(image, completion: completion)
    }
    
    /// Check if auto-redact is enabled and should scan
    var shouldAutoScan: Bool {
        let settings = SettingsManager.shared
        return settings.autoRedactEnabled
    }
    
    /// Get enabled detection types based on settings
    var enabledTypes: Set<SensitiveDataType> {
        var types = Set<SensitiveDataType>()
        let settings = SettingsManager.shared
        
        if settings.redactCreditCards { types.insert(.creditCard) }
        if settings.redactAPIKeys { types.insert(.apiKey) }
        if settings.redactPasswords { types.insert(.password) }
        
        return types
    }
    
    // MARK: - Redaction
    
    /// Apply redaction to specified regions
    func applyRedaction(to image: NSImage, matches: [SensitiveDataMatch], style: RedactionStyle? = nil) -> NSImage {
        let redactionStyle = style ?? currentRedactionStyle
        
        print("🎨 applyRedaction called:")
        print("   Image size: \(image.size)")
        print("   Total matches: \(matches.count)")
        print("   Style: \(redactionStyle.rawValue)")
        
        let regionsToRedact = matches.filter { $0.shouldRedact }.map { $0.boundingBox }
        
        print("   Regions to redact: \(regionsToRedact.count)")
        for (i, region) in regionsToRedact.enumerated() {
            print("   [\(i)] \(region)")
        }
        
        guard !regionsToRedact.isEmpty else { 
            print("   ⚠️ No regions to redact, returning original image")
            return image 
        }
        
        let newImage = NSImage(size: image.size)
        newImage.lockFocus()
        
        // Draw original image
        image.draw(in: NSRect(origin: .zero, size: image.size))
        print("   ✅ Original image drawn")
        
        // Apply redaction to each region
        for (i, region) in regionsToRedact.enumerated() {
            print("   Redacting region \(i)...")
            // TEMP: Force black box for all styles to test position
            applyBlackBox(to: region)
            /*
            switch redactionStyle {
            case .blur:
                applyBlur(to: region, image: image)
            case .pixelate:
                applyPixelation(to: region, image: image)
            case .blackBox:
                applyBlackBox(to: region)
            }
            */
        }
        
        newImage.unlockFocus()
        print("   ✅ Redaction complete, returning new image")
        return newImage
    }
    
    /// Apply redaction to specific rects (for manual redact tool)
    func applyRedaction(to image: NSImage, rects: [CGRect], style: RedactionStyle) -> NSImage {
        guard !rects.isEmpty else { return image }
        
        let newImage = NSImage(size: image.size)
        newImage.lockFocus()
        
        // Draw original image
        image.draw(in: NSRect(origin: .zero, size: image.size))
        
        // Apply redaction to each rect
        for rect in rects {
            switch style {
            case .blur:
                applyBlur(to: rect, image: image)
            case .pixelate:
                applyPixelation(to: rect, image: image)
            case .blackBox:
                applyBlackBox(to: rect)
            }
        }
        
        newImage.unlockFocus()
        return newImage
    }
    
    private var currentRedactionStyle: RedactionStyle {
        RedactionStyle(rawValue: SettingsManager.shared.redactionStyle) ?? .blur
    }
    
    // MARK: - Redaction Effects
    
    private func applyBlur(to rect: CGRect, image: NSImage) {
        print("🔵 Applying BLUR to rect: \(rect)")
        
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("   ❌ No CGImage, falling back to black box")
            applyBlackBox(to: rect)
            return
        }
        
        // Calculate scale factor (Retina = 2x)
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        
        // Expand rect slightly for better coverage
        let expandedRect = rect.insetBy(dx: -4, dy: -4)
        
        // Convert to pixel coordinates for CIImage cropping
        // CIImage uses bottom-left origin (same as NSImage)
        let pixelRect = CGRect(
            x: expandedRect.origin.x * scaleX,
            y: expandedRect.origin.y * scaleY,
            width: expandedRect.width * scaleX,
            height: expandedRect.height * scaleY
        )
        
        let ciImage = CIImage(cgImage: cgImage)
        let croppedCI = ciImage.cropped(to: pixelRect)
        
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            print("   ❌ No blur filter, falling back to black box")
            applyBlackBox(to: rect)
            return
        }
        
        blurFilter.setValue(croppedCI, forKey: kCIInputImageKey)
        blurFilter.setValue(20.0 * scaleX, forKey: kCIInputRadiusKey) // Scale blur radius
        
        guard let outputImage = blurFilter.outputImage else {
            print("   ❌ No output image, falling back to black box")
            applyBlackBox(to: rect)
            return
        }
        
        let context = CIContext()
        // Use original cropped extent to avoid blur edge artifacts
        if let outputCGImage = context.createCGImage(outputImage, from: croppedCI.extent) {
            let blurredNSImage = NSImage(cgImage: outputCGImage, size: expandedRect.size)
            blurredNSImage.draw(in: expandedRect)
            print("   ✅ Blur applied successfully")
        } else {
            print("   ❌ Failed to create blurred image, falling back to black box")
            applyBlackBox(to: rect)
        }
    }
    
    private func applyPixelation(to rect: CGRect, image: NSImage) {
        print("🟡 Applying PIXELATE to rect: \(rect)")
        
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("   ❌ No CGImage, falling back to black box")
            applyBlackBox(to: rect)
            return
        }
        
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        
        let expandedRect = rect.insetBy(dx: -4, dy: -4)
        
        let pixelRect = CGRect(
            x: expandedRect.origin.x * scaleX,
            y: expandedRect.origin.y * scaleY,
            width: expandedRect.width * scaleX,
            height: expandedRect.height * scaleY
        )
        
        let ciImage = CIImage(cgImage: cgImage)
        let croppedCI = ciImage.cropped(to: pixelRect)
        
        guard let pixelateFilter = CIFilter(name: "CIPixellate") else {
            print("   ❌ No pixelate filter, falling back to black box")
            applyBlackBox(to: rect)
            return
        }
        
        pixelateFilter.setValue(croppedCI, forKey: kCIInputImageKey)
        // Center point for pixelation (in image coordinates)
        pixelateFilter.setValue(CIVector(x: pixelRect.midX, y: pixelRect.midY), forKey: kCIInputCenterKey)
        pixelateFilter.setValue(16.0 * scaleX, forKey: kCIInputScaleKey) // Scale pixel size
        
        guard let outputImage = pixelateFilter.outputImage else {
            print("   ❌ No output image, falling back to black box")
            applyBlackBox(to: rect)
            return
        }
        
        let context = CIContext()
        if let outputCGImage = context.createCGImage(outputImage, from: croppedCI.extent) {
            let pixelatedNSImage = NSImage(cgImage: outputCGImage, size: expandedRect.size)
            pixelatedNSImage.draw(in: expandedRect)
            print("   ✅ Pixelate applied successfully")
        } else {
            print("   ❌ Failed to create pixelated image, falling back to black box")
            applyBlackBox(to: rect)
        }
    }
    
    private func applyBlackBox(to rect: CGRect) {
        print("⬛ Applying BLACK BOX to rect: \(rect)")
        let expandedRect = rect.insetBy(dx: -4, dy: -4)
        NSColor.black.setFill()
        let path = NSBezierPath(roundedRect: expandedRect, xRadius: 4, yRadius: 4)
        path.fill()
    }
}

