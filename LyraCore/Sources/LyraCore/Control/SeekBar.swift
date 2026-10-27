import Foundation
import CoreGraphics

/// The arithmetic behind the player's progress bar, kept apart from the view so it can be tested.
public struct SeekBar: Equatable, Sendable {
    public let duration: TimeInterval

    public init(duration: TimeInterval) {
        self.duration = duration
    }

    /// Streams and live radio can report a zero or nonsensical length; those can't be scrubbed.
    public var isSeekable: Bool { duration.isFinite && duration >= 1 }

    /// 0...1 progress of `position`, clamped (a player can briefly report past the end).
    public func fraction(position: TimeInterval) -> Double {
        guard isSeekable, position.isFinite else { return 0 }
        return min(1, max(0, position / duration))
    }

    /// The time a fraction of the bar stands for.
    public func time(forFraction fraction: Double) -> TimeInterval {
        guard isSeekable, fraction.isFinite else { return 0 }
        return min(1, max(0, fraction)) * duration
    }

    /// The fraction under a pointer at `x` in a bar `width` wide, clamped to the bar.
    public func fraction(forX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(1, max(0, Double(x / width)))
    }

    /// "3:07", or "1:02:03" for an hour or more. Negative or invalid times show as "0:00".
    public static func format(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let total = Int(time)
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// Time left, shown with a leading minus like most players: "-1:23".
    public func remainingText(position: TimeInterval) -> String {
        guard isSeekable else { return "--:--" }
        return "-" + Self.format(max(0, duration - position))
    }

    /// Seconds moved by an arrow key or an accessibility increment.
    public static let nudge: TimeInterval = 5
}
