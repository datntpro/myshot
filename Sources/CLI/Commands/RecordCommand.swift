import Foundation
import Cocoa

// MARK: - Record Command
struct RecordCommand {
    static func run(options: [String]) async {
        let parser = OptionParser(args: options)
        
        // Help
        if parser.hasFlag("help", "-h") {
            printHelp()
            return
        }
        
        let outputJSON = parser.hasFlag("json")
        
        // Recording requires GUI interaction with ScreenCaptureKit
        // For CLI, we provide a message about this limitation
        printInfo("Screen recording requires GUI interaction.")
        printInfo("Please use the MyShot app directly for recording.")
        print("")
        print("Hint: You can configure recording settings via:")
        print("  - Format: MP4 (default) or GIF")
        print("  - Quality: Low / Medium / High / Ultra")
        print("  - FPS: 30 or 60")
        print("")
        
        CLIOutput.error("Recording not supported in CLI mode").print(asJSON: outputJSON)
        exit(1)
    }
    
    static func printHelp() {
        print("""
        
        \u{001B}[1mMyShot Record\u{001B}[0m - Record screen
        
        \u{001B}[1mUSAGE:\u{001B}[0m
            myshot record [options]
        
        \u{001B}[1mNOTE:\u{001B}[0m
            Screen recording requires GUI interaction and is not fully
            supported in CLI mode. Please use the MyShot app directly.
        
        \u{001B}[1mOPTIONS:\u{001B}[0m
            --fullscreen        Record entire screen
            --area              Record selected area
            --output, -o PATH   Save to specified path
            --format, -f FMT    Output format: mp4 (default), gif
            --help, -h          Show this help
        
        """)
    }
}
