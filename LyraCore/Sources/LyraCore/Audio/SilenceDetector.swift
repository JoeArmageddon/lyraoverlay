import Foundation

/// Decides whether a running capture has been delivering nothing but digital silence.
///
/// When the System Audio Recording permission is missing, a Core Audio tap does not fail: it
/// delivers buffers of exact zeros. Real audio, even a very quiet fade, is never exactly zero
/// for whole buffers for long, but silence between songs can be, so the verdict is only "no
/// signal for N seconds" and flips back the moment a non-zero sample arrives. A capture that
/// stops delivering buffers entirely counts as silent too (`tick`).
///
/// Time is passed in, so the logic is testable without a clock.
struct SilenceDetector: Equatable {
    enum Verdict: Equatable { case signal, silent }

    let threshold: TimeInterval
    private(set) var verdict: Verdict = .signal
    /// Start of the current run of "nothing but zeros (or no buffers at all)".
    private var quietSince: TimeInterval

    init(threshold: TimeInterval = 4, startingAt now: TimeInterval = 0) {
        self.threshold = threshold
        self.quietSince = now
    }

    mutating func reset(at now: TimeInterval) {
        verdict = .signal
        quietSince = now
    }

    /// Call for every delivered buffer with at least one frame.
    @discardableResult
    mutating func record(allZero: Bool, at now: TimeInterval) -> Verdict {
        if allZero {
            if verdict == .signal, now - quietSince >= threshold { verdict = .silent }
        } else {
            quietSince = now
            verdict = .signal
        }
        return verdict
    }

    /// Call periodically so a capture that delivers no buffers at all is noticed. Buffers that
    /// did arrive with signal keep `quietSince` fresh, so a healthy capture never trips this.
    @discardableResult
    mutating func tick(at now: TimeInterval) -> Verdict {
        if verdict == .signal, now - quietSince >= threshold { verdict = .silent }
        return verdict
    }
}
