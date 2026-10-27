import Foundation

/// Which system API Lyra uses to listen to the Mac's audio output.
public enum AudioCaptureSource: String, Codable, CaseIterable, Sendable, Equatable {
    /// Core Audio process tap (macOS 14.2+). Needs only the narrow "System Audio Recording"
    /// permission, granted once, and no screen capture is involved.
    case systemTap
    /// ScreenCaptureKit audio-only stream. Needs the broad "Screen & System Audio Recording"
    /// permission, whose consent alert macOS repeats. Kept only as an explicit fallback.
    case screenCapture

    public static let `default`: AudioCaptureSource = .systemTap

    public var title: String {
        switch self {
        case .systemTap: return "System audio (recommended)"
        case .screenCapture: return "Screen capture (fallback)"
        }
    }

    /// One line for settings UI.
    public var detail: String {
        switch self {
        case .systemTap: return "Listens to the audio your Mac plays. Asks for System Audio Recording once."
        case .screenCapture: return "Older method. Needs Screen & System Audio Recording and may ask repeatedly."
        }
    }

    /// Short name for logs and the CLI (`tap` / `screen`).
    public var cliName: String {
        switch self {
        case .systemTap: return "tap"
        case .screenCapture: return "screen"
        }
    }

    public init?(cliName: String) {
        guard let match = Self.allCases.first(where: { $0.cliName == cliName.lowercased() }) else { return nil }
        self = match
    }
}
