import Foundation

/// Captures whatever the Mac is playing (never the microphone) and feeds a `FeaturesTracker`.
///
/// The default backend is a Core Audio process tap, which needs only the narrow System Audio
/// Recording permission (granted once) and no screen capture. The old ScreenCaptureKit stream
/// stays available with `source: .screenCapture`.
///
/// The state machine, mono conversion and silence detection are shared by both backends.
public final class SystemAudioCapture: @unchecked Sendable, AudioCaptureSink {
    public enum State: Equatable, Sendable {
        case stopped
        case starting
        case capturing
        /// The capture runs but only digital silence arrives. Either nothing is playing, or the
        /// System Audio Recording permission is missing (macOS then delivers zeros, not an error).
        case noSignal
        /// An error that clearly means the recording permission is missing or revoked.
        case permissionDenied
        case failed(String)
    }

    /// Fallback sample rate until the backend reports the real one.
    public static let sampleRate = 48_000.0

    /// System Settings > Privacy & Security > Microphone-style pane for "System Audio Recording"
    /// (privacy category Audio Recording).
    public static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
    /// Pane for the broad Screen & System Audio Recording permission (the `.screenCapture` fallback).
    public static let screenCapturePrivacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    /// Human explanation for `.noSignal`, ready for a menu or settings row.
    public static let noSignalExplanation =
        "No audio is arriving: either nothing is playing, or System Audio Recording permission is missing."

    public let tracker: FeaturesTracker
    public let source: AudioCaptureSource

    private let backend: AudioCaptureBackend
    private let clock: @Sendable () -> TimeInterval
    private let lock = NSLock()
    private var machine = CaptureStateMachine()
    private var detector: SilenceDetector
    private var timer: DispatchSourceTimer?

    /// Called on an arbitrary thread whenever the state changes.
    public var onStateChange: (@Sendable (State) -> Void)?

    public var state: State { lock.withLock { machine.state } }

    public convenience init(tracker: FeaturesTracker = FeaturesTracker(sampleRate: SystemAudioCapture.sampleRate),
                            source: AudioCaptureSource = .default) {
        self.init(tracker: tracker, source: source, backend: Self.makeBackend(for: source))
    }

    /// Seam for tests: any backend, a fake clock and a short silence threshold.
    init(tracker: FeaturesTracker = FeaturesTracker(sampleRate: SystemAudioCapture.sampleRate),
         source: AudioCaptureSource = .default,
         backend: AudioCaptureBackend,
         silenceThreshold: TimeInterval = 4,
         clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.tracker = tracker
        self.source = source
        self.backend = backend
        self.clock = clock
        self.detector = SilenceDetector(threshold: silenceThreshold, startingAt: clock())
    }

    deinit { timer?.cancel() }

    static func makeBackend(for source: AudioCaptureSource) -> AudioCaptureBackend {
        switch source {
        case .systemTap:
            if #available(macOS 14.2, *) { return ProcessTapBackend() }
            return ScreenCaptureBackend()   // unreachable on the macOS 14.2+ the app targets in practice
        case .screenCapture:
            return ScreenCaptureBackend()
        }
    }

    // MARK: - Start / stop

    /// Idempotent: does nothing while starting or running.
    public func start() async {
        guard let generation = lock.withLock({ machine.beginStart() }) else { return }
        notify(.starting)
        do {
            let rate = try await backend.start(sink: self)
            tracker.reconfigure(sampleRate: rate)
            tracker.reset()
            let ok: Bool = lock.withLock {
                detector.reset(at: clock())
                return machine.finishStart(generation: generation)
            }
            if ok {
                startTimer()
                notify(.capturing)
            } else {
                await backend.stop()    // stop() overtook this start
            }
        } catch {
            let new = Self.state(for: error)
            let changed = lock.withLock { machine.failStart(generation: generation, as: new) }
            await backend.stop()
            if changed { notify(new) }
        }
    }

    /// Idempotent and safe to call from any state.
    public func stop() async {
        let changed = lock.withLock { machine.stop() }
        cancelTimer()
        await backend.stop()
        if changed { notify(.stopped) }
    }

    static func state(for error: Error) -> State {
        switch error as? AudioCaptureError {
        case .permissionDenied?: return .permissionDenied
        case .failed(let message)?: return .failed(message)
        case nil: return .failed((error as NSError).localizedDescription)
        }
    }

    // MARK: - Backend sink

    func backend(didProduce mono: [Float], allZero: Bool) {
        tracker.ingest(mono)
        let now = clock()
        let change: State? = lock.withLock {
            let verdict = detector.record(allZero: allZero, at: now)
            return machine.apply(verdict) ? machine.state : nil
        }
        if let change { notify(change) }
    }

    func backend(didChangeSampleRate rate: Double) {
        tracker.reconfigure(sampleRate: rate)
        lock.withLock { detector.reset(at: clock()) }
    }

    func backend(didFail error: AudioCaptureError) {
        let new = Self.state(for: error)
        let changed = lock.withLock { machine.backendFailed(new) }
        guard changed else { return }
        cancelTimer()
        notify(new)
        Task { [backend] in await backend.stop() }
    }

    // MARK: - Silence watchdog

    /// Also called by the timer; internal so tests can drive it with a fake clock.
    func tickSilence() {
        let now = clock()
        let change: State? = lock.withLock {
            let verdict = detector.tick(at: now)
            return machine.apply(verdict) ? machine.state : nil
        }
        if let change { notify(change) }
    }

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "lyra.audio-capture.watchdog", qos: .utility))
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self?.tickSilence() }
        let old: DispatchSourceTimer? = lock.withLock { let o = timer; timer = t; return o }
        old?.cancel()
        t.resume()
    }

    private func cancelTimer() {
        let old: DispatchSourceTimer? = lock.withLock { let o = timer; timer = nil; return o }
        old?.cancel()
    }

    private func notify(_ s: State) { onStateChange?(s) }
}
