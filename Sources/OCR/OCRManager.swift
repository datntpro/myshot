import Cocoa
import Vision

// MARK: - OCR Manager
class OCRManager {
    static let shared = OCRManager()
    
    private init() {}
    
    // MARK: - Text Recognition
    func recognizeText(from image: NSImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(nil)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    print("OCR error: \(error)")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                // Extract text from all observations
                let recognizedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")
                
                DispatchQueue.main.async {
                    completion(recognizedText.isEmpty ? nil : recognizedText)
                }
            }
            
            // Configure the request
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "vi-VN"] // English and Vietnamese
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("Failed to perform OCR: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    // MARK: - Quick OCR from clipboard
    func performOCRFromClipboard(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        
        guard let image = NSImage(pasteboard: pasteboard) else {
            completion(nil)
            return
        }
        
        recognizeText(from: image, completion: completion)
    }
    
    // MARK: - Get text with bounding boxes
    func recognizeTextWithBounds(from image: NSImage, completion: @escaping ([(String, CGRect)]) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion([])
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    print("OCR error: \(error)")
                    DispatchQueue.main.async {
                        completion([])
                    }
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    DispatchQueue.main.async {
                        completion([])
                    }
                    return
                }
                
                let results = observations.compactMap { observation -> (String, CGRect)? in
                    guard let candidate = observation.topCandidates(1).first else {
                        return nil
                    }
                    
                    // Convert normalized coordinates to image coordinates
                    let imageHeight = CGFloat(cgImage.height)
                    let imageWidth = CGFloat(cgImage.width)
                    
                    let boundingBox = observation.boundingBox
                    let rect = CGRect(
                        x: boundingBox.origin.x * imageWidth,
                        y: (1 - boundingBox.origin.y - boundingBox.height) * imageHeight,
                        width: boundingBox.width * imageWidth,
                        height: boundingBox.height * imageHeight
                    )
                    
                    return (candidate.string, rect)
                }
                
                DispatchQueue.main.async {
                    completion(results)
                }
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("Failed to perform OCR: \(error)")
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }
}
