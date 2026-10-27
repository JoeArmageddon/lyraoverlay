import Foundation

public enum ScriptError: Error, Equatable {
    /// macOS Automation permission for the target app was denied or not yet granted.
    case notAuthorized
    case failed(code: Int, message: String)
}

private final class Once: @unchecked Sendable {
    let lock = NSLock()
    var resumed = false
}

/// Runs AppleScript through `/usr/bin/osascript`.
///
/// `NSAppleScript` is documented as main-thread only, and running it on a
/// background queue intermittently stalled polling. A subprocess is thread-safe,
/// can be killed if the target app hangs, and Automation permission is still
/// attributed to the app that launched it.
final class AppleScriptRunner: @unchecked Sendable {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 4) { self.timeout = timeout }

    func run(_ source: String) async -> Result<String, ScriptError> {
        await withCheckedContinuation { cont in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let stdout = Pipe(), stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            // The termination handler and the timeout can race; resume exactly once.
            let once = Once()
            let finish: @Sendable (Result<String, ScriptError>) -> Void = { result in
                once.lock.lock(); defer { once.lock.unlock() }
                guard !once.resumed else { return }
                once.resumed = true
                cont.resume(returning: result)
            }

            process.terminationHandler = { proc in
                let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if proc.terminationStatus == 0 {
                    finish(.success(out.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))))
                } else {
                    finish(.failure(Self.error(fromStderr: err)))
                }
            }

            do {
                try process.run()
            } catch {
                finish(.failure(.failed(code: -1, message: "could not launch osascript: \(error)")))
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                    finish(.failure(.failed(code: -2, message: "timed out after \(Int(self.timeout))s")))
                }
            }
        }
    }

    /// osascript reports errors as "... message. (-1743)" on stderr.
    static func error(fromStderr stderr: String) -> ScriptError {
        let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        var code = -1
        if let range = text.range(of: #"\((-?\d+)\)\s*$"#, options: .regularExpression) {
            let digits = text[range].trimmingCharacters(in: CharacterSet(charactersIn: "() \n"))
            code = Int(digits) ?? -1
        }
        // -1743: not authorized to send Apple events.
        return code == -1743 ? .notAuthorized : .failed(code: code, message: text)
    }
}
