import Foundation

/// The pure state machine behind `SystemAudioCapture`. No locking here: the owner serializes calls.
struct CaptureStateMachine {
    typealias State = SystemAudioCapture.State

    private(set) var state: State = .stopped
    /// Bumped by every stop, so a start that finished late can tell it was cancelled.
    private(set) var generation = 0

    /// Returns the generation to carry through the start, or nil when a start is not allowed
    /// (already starting or running: starting is idempotent).
    mutating func beginStart() -> Int? {
        switch state {
        case .stopped, .permissionDenied, .failed:
            state = .starting
            return generation
        case .starting, .capturing, .noSignal:
            return nil
        }
    }

    /// The backend came up. False when stop() or a newer attempt overtook this start.
    mutating func finishStart(generation g: Int) -> Bool {
        guard state == .starting, g == generation else { return false }
        state = .capturing
        return true
    }

    /// A start attempt failed. Ignored when it was cancelled meanwhile.
    mutating func failStart(generation g: Int, as new: State) -> Bool {
        guard state == .starting, g == generation else { return false }
        state = new
        return true
    }

    /// The running backend reported an error. Ignored once stopped.
    mutating func backendFailed(_ new: State) -> Bool {
        switch state {
        case .starting, .capturing, .noSignal:
            state = new
            return true
        case .stopped, .permissionDenied, .failed:
            return false
        }
    }

    /// Silence verdict from the detector. Only meaningful while a capture is running.
    mutating func apply(_ verdict: SilenceDetector.Verdict) -> Bool {
        switch (state, verdict) {
        case (.capturing, .silent):
            state = .noSignal
            return true
        case (.noSignal, .signal):
            state = .capturing
            return true
        default:
            return false
        }
    }

    /// Always lands in .stopped. Returns whether the state changed.
    mutating func stop() -> Bool {
        generation += 1
        guard state != .stopped else { return false }
        state = .stopped
        return true
    }
}
