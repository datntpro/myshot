import Foundation
import Vision
import Cocoa

// MARK: - Sensitive Data Types
enum SensitiveDataType: String, CaseIterable {
    case creditCard = "Credit Card"
    case apiKey = "API Key"
    case password = "Password"
    
    var icon: String {
        switch self {
        case .creditCard: return "creditcard"
        case .apiKey: return "key"
        case .password: return "lock"
        }
    }
}

// MARK: - Sensitive Data Match
struct SensitiveDataMatch: Identifiable {
    let id = UUID()
    let type: SensitiveDataType
    let text: String
    let boundingBox: CGRect
    let confidence: Double
    var shouldRedact: Bool = true
    
    // Masked version for preview (e.g., "4111 **** **** 1234")
    var maskedText: String {
        switch type {
        case .creditCard:
            if text.count >= 8 {
                let first4 = String(text.prefix(4))
                let last4 = String(text.suffix(4))
                return "\(first4) •••• •••• \(last4)"
            }
            return "•••• •••• •••• ••••"
        case .apiKey:
            if text.count > 8 {
                return String(text.prefix(4)) + "••••••••" + String(text.suffix(4))
            }
            return "••••••••••••"
        case .password:
            return "••••••••"
        }
    }
}

// MARK: - Sensitive Data Detector
class SensitiveDataDetector {
    static let shared = SensitiveDataDetector()
    
    private init() {}
    
    // MARK: - Credit Card Patterns
    // Visa: 4xxx xxxx xxxx xxxx
    // Mastercard: 5[1-5]xx xxxx xxxx xxxx
    // Amex: 3[47]xx xxxxxx xxxxx
    // Discover: 6011 xxxx xxxx xxxx
    private let creditCardPatterns: [String] = [
        // Visa (starts with 4, 13-16 digits)
        #"4[0-9]{12}(?:[0-9]{3})?"#,
        // Mastercard (starts with 51-55 or 2221-2720, 16 digits)
        #"5[1-5][0-9]{14}"#,
        #"2(?:2[2-9][1-9]|[3-6][0-9]{2}|7[01][0-9]|720)[0-9]{12}"#,
        // Amex (starts with 34 or 37, 15 digits)
        #"3[47][0-9]{13}"#,
        // Discover (starts with 6011, 6221-6229, 644-649, 65, 16 digits)
        #"6(?:011|22[1-9]|[45][0-9]{2})[0-9]{12}"#,
        // Generic pattern with spaces/dashes
        #"\b(?:\d{4}[-\s]?){3}\d{4}\b"#,
        #"\b\d{4}[-\s]?\d{6}[-\s]?\d{5}\b"#, // Amex format
    ]
    
    // MARK: - API Key Patterns
    private let apiKeyPatterns: [String] = [
        // AWS Access Key ID
        #"(?:A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{16}"#,
        // AWS Secret Access Key
        #"(?i)aws(.{0,20})?(?-i)['\"][0-9a-zA-Z\/+]{40}['\"]"#,
        // GitHub Token (classic) - typically 36-40 chars but be lenient
        #"ghp_[a-zA-Z0-9]{20,50}"#,
        // GitHub Token (fine-grained)
        #"github_pat_[a-zA-Z0-9]{22}_[a-zA-Z0-9]{40,}"#,
        // Stripe API Key
        #"sk_live_[a-zA-Z0-9]{24,}"#,
        #"sk_test_[a-zA-Z0-9]{24,}"#,
        #"pk_live_[a-zA-Z0-9]{24,}"#,
        #"pk_test_[a-zA-Z0-9]{24,}"#,
        // OpenAI API Key
        #"sk-[a-zA-Z0-9]{20,}"#,
        #"sk-proj-[a-zA-Z0-9]{20,}"#,
        // Generic API key patterns
        #"(?i)(api[_-]?key|apikey|api[_-]?secret|api[_-]?token)['\"]?\s*[:=]\s*['\"]?[a-zA-Z0-9_\-]{20,}['\"]?"#,
        #"(?i)(access[_-]?token|auth[_-]?token|bearer)\s*[:=]\s*['\"]?[a-zA-Z0-9_\-\.]{20,}['\"]?"#,
        // Generic secret patterns
        #"(?i)(secret|private[_-]?key|client[_-]?secret)['\"]?\s*[:=]\s*['\"]?[a-zA-Z0-9_\-]{16,}['\"]?"#,
    ]
    
    // MARK: - Password Patterns
    private let passwordPatterns: [String] = [
        // Password in key-value format
        #"(?i)(password|passwd|pwd|pass)\s*[:=]\s*['\"]?[^\s'\",]{4,}['\"]?"#,
        // Password in JSON
        #"(?i)['\"]password['\"]\s*:\s*['\"][^'\"]+['\"]"#,
        // Password in config files
        #"(?i)password\s*=\s*[^\s]+"#,
        // Database connection strings with password
        #"(?i)(mysql|postgresql|mongodb|redis)://[^:]+:([^@]+)@"#,
    ]
    
    // MARK: - Detection Methods
    
    /// Detect sensitive data in text
    func detectInText(_ text: String) -> [(type: SensitiveDataType, match: String, range: Range<String.Index>)] {
        var results: [(type: SensitiveDataType, match: String, range: Range<String.Index>)] = []
        
        // Check credit cards
        for pattern in creditCardPatterns {
            let matches = findMatches(pattern: pattern, in: text)
            for (matchText, range) in matches {
                // Validate with Luhn algorithm for credit cards
                let digitsOnly = matchText.filter { $0.isNumber }
                if isValidCreditCard(digitsOnly) {
                    results.append((type: .creditCard, match: matchText, range: range))
                }
            }
        }
        
        // Check API keys
        for pattern in apiKeyPatterns {
            let matches = findMatches(pattern: pattern, in: text)
            for (matchText, range) in matches {
                results.append((type: .apiKey, match: matchText, range: range))
            }
        }
        
        // Check passwords
        for pattern in passwordPatterns {
            let matches = findMatches(pattern: pattern, in: text)
            for (matchText, range) in matches {
                results.append((type: .password, match: matchText, range: range))
            }
        }
        
        return results
    }
    
    /// Detect sensitive data in image using OCR
    func detectInImage(_ image: NSImage, completion: @escaping ([SensitiveDataMatch]) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ Failed to get CGImage from NSImage")
            completion([])
            return
        }
        
        print("🔍 OCR: Starting text recognition...")
        print("   Image dimensions: \(cgImage.width) x \(cgImage.height)")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    print("❌ OCR Error: \(error)")
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    print("❌ OCR: No observations returned")
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                
                print("📝 OCR: Found \(observations.count) text blocks")
                
                var matches: [SensitiveDataMatch] = []
                // IMPORTANT: Use NSImage.size (points) not cgImage dimensions (pixels)
                // On Retina displays, cgImage is 2x the NSImage.size
                let imageWidth = image.size.width
                let imageHeight = image.size.height
                
                // First, collect ALL text for debugging
                var allText: [String] = []
                for observation in observations {
                    if let candidate = observation.topCandidates(1).first {
                        allText.append(candidate.string)
                    }
                }
                print("📃 OCR Extracted Text:")
                for (i, text) in allText.enumerated() {
                    print("   [\(i)]: \(text)")
                }
                
                // Now scan for sensitive data
                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let text = candidate.string
                    
                    // Detect sensitive data in this text block
                    let detections = self.detectInText(text)
                    
                    if !detections.isEmpty {
                        print("🚨 Found \(detections.count) match(es) in: \"\(text)\"")
                        for d in detections {
                            print("   → \(d.type.rawValue): \(d.match)")
                        }
                    }
                    
                    for detection in detections {
                        // Convert normalized bounding box to image coordinates
                        // VNRecognizedTextObservation.boundingBox is normalized (0-1) with bottom-left origin
                        // NSImage/NSView also uses bottom-left origin, so just scale - no flip needed
                        let boundingBox = observation.boundingBox
                        let rect = CGRect(
                            x: boundingBox.origin.x * imageWidth,
                            y: boundingBox.origin.y * imageHeight,
                            width: boundingBox.width * imageWidth,
                            height: boundingBox.height * imageHeight
                        )
                        
                        print("   📍 BoundingBox for '\(detection.match.prefix(15))...': \(rect)")
                        
                        let match = SensitiveDataMatch(
                            type: detection.type,
                            text: detection.match,
                            boundingBox: rect,
                            confidence: Double(candidate.confidence)
                        )
                        matches.append(match)
                    }
                }
                
                print("✅ OCR Complete: \(matches.count) sensitive items detected")
                
                DispatchQueue.main.async {
                    completion(matches)
                }
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false // Preserve original text (e.g., API keys)
            request.recognitionLanguages = ["en-US"] // Focus on English for API keys/credit cards
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("❌ Failed to perform OCR: \(error)")
                DispatchQueue.main.async { completion([]) }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func findMatches(pattern: String, in text: String) -> [(String, Range<String.Index>)] {
        var results: [(String, Range<String.Index>)] = []
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)
            
            for match in matches {
                if let swiftRange = Range(match.range, in: text) {
                    let matchedText = String(text[swiftRange])
                    results.append((matchedText, swiftRange))
                }
            }
        } catch {
            print("Invalid regex pattern: \(pattern)")
        }
        
        return results
    }
    
    /// Luhn algorithm for credit card validation
    private func isValidCreditCard(_ number: String) -> Bool {
        guard number.count >= 13 && number.count <= 19 else { return false }
        
        var sum = 0
        let digits = number.reversed().map { Int(String($0)) ?? 0 }
        
        for (index, digit) in digits.enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        
        return sum % 10 == 0
    }
}
