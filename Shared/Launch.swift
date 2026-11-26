import Foundation

enum Launch {
    static let freePeriod = true
    static let arguments = ProcessInfo.processInfo.arguments
    static var testing: Bool {
        #if DEBUG
        arguments.contains("-ui-testing")
        #else
        false
        #endif
    }
    static var seed: Bool { testing && arguments.contains("-seed") }
    static var reset: Bool { testing && arguments.contains("-reset") }
}
