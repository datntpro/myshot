import Foundation

// MARK: - CLI Main Entry Point
@main
struct MyShotCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        
        if args.isEmpty {
            printUsage()
            exit(0)
        }
        
        let command = args[0].lowercased()
        let options = Array(args.dropFirst())
        
        switch command {
        case "--help", "-h", "help":
            printUsage()
        case "--version", "-v", "version":
            printVersion()
        case "capture":
            await CaptureCommand.run(options: options)
        case "record":
            await RecordCommand.run(options: options)
        case "ocr":
            await OCRCommand.run(options: options)
        case "annotate":
            await AnnotateCommand.run(options: options)
        default:
            printError("Unknown command: \(command)")
            printUsage()
            exit(1)
        }
    }
    
    static func printUsage() {
        let usage = """
        
        \u{001B}[1mMyShot CLI\u{001B}[0m - Screenshot & Screen Recording Tool
        
        \u{001B}[1mUSAGE:\u{001B}[0m
            myshot <command> [options]
        
        \u{001B}[1mCOMMANDS:\u{001B}[0m
            capture     Take a screenshot
            record      Record screen (video or GIF)
            ocr         Extract text from image
            annotate    Open annotation editor
        
        \u{001B}[1mGLOBAL OPTIONS:\u{001B}[0m
            --help, -h      Show this help message
            --version, -v   Show version information
        
        \u{001B}[1mEXAMPLES:\u{001B}[0m
            myshot capture --area
            myshot capture --fullscreen --output ~/Desktop/shot.png
            myshot capture --area --redact --copy
            myshot record --area --format gif
            myshot ocr ~/path/to/image.png --json
            myshot annotate ~/path/to/image.png
        
        Use 'myshot <command> --help' for more information about a command.
        
        """
        print(usage)
    }
    
    static func printVersion() {
        print("MyShot CLI v1.0.0")
        print("Copyright © 2024 1Vision")
    }
}

// MARK: - CLI Helpers
func printError(_ message: String) {
    FileHandle.standardError.write(Data("\u{001B}[31mError:\u{001B}[0m \(message)\n".utf8))
}

func printSuccess(_ message: String) {
    print("\u{001B}[32m✓\u{001B}[0m \(message)")
}

func printInfo(_ message: String) {
    print("\u{001B}[34mℹ\u{001B}[0m \(message)")
}

// MARK: - JSON Output
struct CLIOutput: Codable {
    let success: Bool
    let data: OutputData?
    let error: String?
    
    enum OutputData: Codable {
        case text(String)
        case file(path: String)
        case ocrResult(text: String, lines: Int, words: Int)
        
        enum CodingKeys: String, CodingKey {
            case type, value, path, text, lines, words
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let value):
                try container.encode("text", forKey: .type)
                try container.encode(value, forKey: .value)
            case .file(let path):
                try container.encode("file", forKey: .type)
                try container.encode(path, forKey: .path)
            case .ocrResult(let text, let lines, let words):
                try container.encode("ocr", forKey: .type)
                try container.encode(text, forKey: .text)
                try container.encode(lines, forKey: .lines)
                try container.encode(words, forKey: .words)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "text":
                self = .text(try container.decode(String.self, forKey: .value))
            case "file":
                self = .file(path: try container.decode(String.self, forKey: .path))
            case "ocr":
                self = .ocrResult(
                    text: try container.decode(String.self, forKey: .text),
                    lines: try container.decode(Int.self, forKey: .lines),
                    words: try container.decode(Int.self, forKey: .words)
                )
            default:
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown type"))
            }
        }
    }
    
    static func success(_ data: OutputData) -> CLIOutput {
        CLIOutput(success: true, data: data, error: nil)
    }
    
    static func error(_ message: String) -> CLIOutput {
        CLIOutput(success: false, data: nil, error: message)
    }
    
    func print(asJSON: Bool) {
        if asJSON {
            if let jsonData = try? JSONEncoder().encode(self),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                Swift.print(jsonString)
            }
        } else {
            if let error = error {
                printError(error)
            } else if let data = data {
                switch data {
                case .text(let value):
                    Swift.print(value)
                case .file(let path):
                    printSuccess("Saved to: \(path)")
                case .ocrResult(let text, _, _):
                    Swift.print(text)
                }
            }
        }
    }
}

// MARK: - Option Parser
struct OptionParser {
    let args: [String]
    
    func hasFlag(_ flags: String...) -> Bool {
        for flag in flags {
            if args.contains(flag) || args.contains("--\(flag)") {
                return true
            }
        }
        return false
    }
    
    func getValue(for flags: String...) -> String? {
        for flag in flags {
            if let index = args.firstIndex(of: flag) ?? args.firstIndex(of: "--\(flag)"),
               index + 1 < args.count {
                return args[index + 1]
            }
        }
        return nil
    }
    
    func getPositionalArg(at index: Int) -> String? {
        let positional = args.filter { !$0.hasPrefix("-") }
        guard index < positional.count else { return nil }
        return positional[index]
    }
}
