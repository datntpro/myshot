import Foundation
import Cocoa

// MARK: - Annotate Command
struct AnnotateCommand {
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
            CLIOutput.error("No image path provided. Usage: myshot annotate <image_path>").print(asJSON: outputJSON)
            exit(1)
        }
        
        let expandedPath = (imagePath as NSString).expandingTildeInPath
        
        // Check file exists
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            CLIOutput.error("File not found: \(expandedPath)").print(asJSON: outputJSON)
            exit(1)
        }
        
        // Annotation requires GUI - open the image with the MyShot app
        printInfo("Opening annotation editor...")
        
        // Try to open with MyShot app, fallback to Preview
        let workspace = NSWorkspace.shared
        let fileURL = URL(fileURLWithPath: expandedPath)
        
        // Try opening with MyShot.app if installed
        let myshotAppPath = "/Applications/MyShot.app"
        if FileManager.default.fileExists(atPath: myshotAppPath) {
            let myshotURL = URL(fileURLWithPath: myshotAppPath)
            workspace.open([fileURL], withApplicationAt: myshotURL, configuration: .init()) { app, error in
                if let error = error {
                    // Fallback to Preview
                    workspace.open(fileURL)
                }
            }
        } else {
            // Fallback to system default (Preview)
            workspace.open(fileURL)
        }
        
        CLIOutput.success(.text("Opened annotation editor")).print(asJSON: outputJSON)
    }
    
    static func printHelp() {
        print("""
        
        \u{001B}[1mMyShot Annotate\u{001B}[0m - Open annotation editor
        
        \u{001B}[1mUSAGE:\u{001B}[0m
            myshot annotate <image_path> [options]
        
        \u{001B}[1mDESCRIPTION:\u{001B}[0m
            Opens the image in MyShot's annotation editor for adding
            arrows, text, shapes, blur, and other annotations.
        
        \u{001B}[1mOPTIONS:\u{001B}[0m
            --json          Output result as JSON
            --help, -h      Show this help
        
        \u{001B}[1mEXAMPLES:\u{001B}[0m
            myshot annotate ~/Desktop/screenshot.png
        
        """)
    }
}
