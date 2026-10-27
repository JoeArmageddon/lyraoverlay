import Foundation

/// Opt-in diagnostics on stderr: set `LYRA_DEBUG=1`.
enum Debug {
    static let enabled = ProcessInfo.processInfo.environment["LYRA_DEBUG"] != nil

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data("[lyra] \(message())\n".utf8))
    }
}
