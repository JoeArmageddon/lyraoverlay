import Foundation

/// What a backend reports back to `SystemAudioCapture`. Called on arbitrary threads.
protocol AudioCaptureSink: AnyObject {
    /// One buffer converted to mono. `allZero` is true when every sample was exactly 0.0.
    func backend(didProduce mono: [Float], allZero: Bool)
    /// The input sample rate changed after start (the tap was rebuilt on another output device).
    func backend(didChangeSampleRate rate: Double)
    /// The running capture died and cannot continue by itself.
    func backend(didFail error: AudioCaptureError)
}

enum AudioCaptureError: Error, Equatable {
    /// The error clearly means the user has not allowed (or revoked) the recording permission.
    case permissionDenied
    case failed(String)
}

/// One way of getting system audio. Both backends feed the same conversion, silence
/// detection and state machine in `SystemAudioCapture`.
protocol AudioCaptureBackend: AnyObject, Sendable {
    /// Starts delivering to `sink` and returns the input sample rate in Hz. Idempotent:
    /// starting a running backend restarts it cleanly.
    func start(sink: AudioCaptureSink) async throws -> Double
    /// Stops delivering and releases every system resource. Safe to call repeatedly.
    func stop() async
}
