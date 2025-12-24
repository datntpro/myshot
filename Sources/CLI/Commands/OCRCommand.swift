import Foundation
import Cocoa
import Vision

// MARK: - OCR Command
struct OCRCommand {
    static func run(options: [String]) async {
        let parser = OptionParser(args: options)
        
        // Help
        if parser.hasFlag("help", "-h") {
            printHelp()
            return
        }
        
        let outputJSON = parser.hasFlag("json")
        
        // Get image path
        guard let imagePath = parser.getPositionalArg(at: 0) else {
            CLIOutput.error("No image path provided. Usage: myshot ocr <image_path>").print(asJSON: outputJSON)
            exit(1)
        }
        
        let expandedPath = (imagePath as NSString).expandingTildeInPath
        
        // Check file exists
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            CLIOutput.error("File not found: \(expandedPath)").print(asJSON: outputJSON)
            exit(1)
        }
        
        // Load image
        guard let image = NSImage(contentsOfFile: expandedPath) else {
            CLIOutput.error("Failed to load image: \(expandedPath)").print(asJSON: outputJSON)
            exit(1)
        }
        
        // Perform OCR
        do {
            let text = try await performOCR(on: image)
            let lines = text.components(separatedBy: "\n").count
            let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
            
            CLIOutput.success(.ocrResult(text: text, lines: lines, words: words)).print(asJSON: outputJSON)
        } catch {
            CLIOutput.error(error.localizedDescription).print(asJSON: outputJSON)
            exit(1)
        }
    }
    
    static func printHelp() {
        print("""
        
        \u{001B}[1mMyShot OCR\u{001B}[0m - Extract text from images
        
        \u{001B}[1mUSAGE:\u{001B}[0m
            myshot ocr <image_path> [options]
        
        \u{001B}[1mOPTIONS:\u{001B}[0m
            --json          Output result as JSON
            --help, -h      Show this help
        
        \u{001B}[1mEXAMPLES:\u{001B}[0m
            myshot ocr ~/Desktop/screenshot.png
            myshot ocr ~/Desktop/screenshot.png --json
        
        """)
    }
    
    static func performOCR(on image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: OCRError.noResults)
                    return
                }
                
                let text = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")
                
                continuation.resume(returning: text.isEmpty ? "" : text)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "vi-VN"]
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    enum OCRError: LocalizedError {
        case invalidImage
        case noResults
        
        var errorDescription: String? {
            switch self {
            case .invalidImage: return "Invalid or corrupted image"
            case .noResults: return "No text found in image"
            }
        }
    }
}
