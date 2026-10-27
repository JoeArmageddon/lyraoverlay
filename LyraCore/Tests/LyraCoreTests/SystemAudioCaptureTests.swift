import XCTest
import AudioToolbox
@testable import LyraCore

/// Everything here uses synthetic data and a fake backend: no tap, no stream, no permission prompt.
final class AudioConversionTests: XCTestCase {
    private func convert(_ buffers: [[Float]], channelsPerBuffer: Int) -> (samples: [Float], frames: Int, allZero: Bool) {
        var storage = buffers
        var out: [Float] = []
        var descriptors: [(data: UnsafeMutableRawPointer?, byteSize: Int, channels: Int)] = []
        var pointers: [UnsafeMutablePointer<Float>] = []
        for i in storage.indices {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: max(1, storage[i].count))
            p.update(from: storage[i], count: storage[i].count)
            pointers.append(p)
            descriptors.append((UnsafeMutableRawPointer(p), storage[i].count * 4, channelsPerBuffer))
        }
        defer { pointers.forEach { $0.deallocate() } }
        storage.removeAll()
        let r = AudioSampleConversion.mono(from: descriptors, into: &out)
        return (out, r.frames, r.allZero)
    }

    func testInterleavedStereoAveragesChannels() {
        let r = convert([[1, 0, 0.5, 0.5, -1, 1]], channelsPerBuffer: 2)
        XCTAssertEqual(r.samples, [0.5, 0.5, 0])
        XCTAssertFalse(r.allZero)
    }

    func testPlanarStereoAveragesChannels() {
        let r = convert([[1, 1, 1], [0, 0.5, -1]], channelsPerBuffer: 1)
        XCTAssertEqual(r.samples, [0.5, 0.75, 0])
    }

    func testMonoPassesThrough() {
        XCTAssertEqual(convert([[0.1, 0.2, 0.3]], channelsPerBuffer: 1).samples, [0.1, 0.2, 0.3])
    }

    func testOddChannelCounts() {
        // 3 interleaved channels
        XCTAssertEqual(convert([[3, 0, 0, 0, 6, 0]], channelsPerBuffer: 3).samples, [1, 2])
        // 5 planar channels
        let planar = convert([[5], [0], [0], [0], [0]], channelsPerBuffer: 1)
        XCTAssertEqual(planar.samples, [1])
        // 6 interleaved channels, 2 frames
        XCTAssertEqual(convert([[6, 6, 6, 6, 6, 6, 0, 0, 0, 0, 0, 0]], channelsPerBuffer: 6).samples, [6, 0])
    }

    func testShortestPlaneLimitsFramesAndNeverReadsPastIt() {
        let r = convert([[1, 1, 1, 1], [1, 1]], channelsPerBuffer: 1)
        XCTAssertEqual(r.frames, 2)
        XCTAssertEqual(r.samples, [1, 1])
    }

    func testDigitalSilenceIsDetectedExactly() {
        XCTAssertTrue(convert([[0, 0, 0, 0]], channelsPerBuffer: 2).allZero)
        XCTAssertFalse(convert([[0, 0, 0, 1e-9]], channelsPerBuffer: 2).allZero)
    }

    func testEmptyAndNonFiniteInput() {
        XCTAssertEqual(convert([[]], channelsPerBuffer: 2).frames, 0)
        let r = convert([[.nan, .infinity]], channelsPerBuffer: 1)
        XCTAssertEqual(r.samples, [0, 0])
        XCTAssertTrue(r.allZero)
    }

    func testRealAudioBufferListInterleavedAndPlanar() {
        // Build genuine AudioBufferLists, as Core Audio hands to an IOProc.
        let frames = 4
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        var l = [Float](repeating: 0.2, count: frames), r = [Float](repeating: 0.4, count: frames)
        l.withUnsafeMutableBytes { lb in r.withUnsafeMutableBytes { rb in
            list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(lb.count), mData: lb.baseAddress)
            list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(rb.count), mData: rb.baseAddress)
            var out: [Float] = []
            let result = AudioSampleConversion.mono(from: list.unsafePointer, into: &out)
            XCTAssertEqual(result.frames, frames)
            XCTAssertEqual(out, [Float](repeating: 0.3, count: frames))
        } }
        var inter: [Float] = [0.2, 0.4, 0.2, 0.4]
        inter.withUnsafeMutableBytes { b in
            let one = AudioBufferList.allocate(maximumBuffers: 1)
            one[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(b.count), mData: b.baseAddress)
            var out: [Float] = []
            XCTAssertEqual(AudioSampleConversion.mono(from: one.unsafePointer, into: &out).frames, 2)
            XCTAssertEqual(out, [0.3, 0.3])
            free(one.unsafeMutablePointer)
        }
        free(list.unsafeMutablePointer)
    }
}

final class SilenceDetectorTests: XCTestCase {
    func testTripsOnlyAfterThresholdOfExactZeros() {
        var d = SilenceDetector(threshold: 3, startingAt: 0)
        XCTAssertEqual(d.record(allZero: true, at: 1), .signal)
        XCTAssertEqual(d.record(allZero: true, at: 2.9), .signal)
        XCTAssertEqual(d.record(allZero: true, at: 3.0), .silent)
    }

    func testAnySignalResetsTheClockAndRecovers() {
        var d = SilenceDetector(threshold: 3, startingAt: 0)
        d.record(allZero: true, at: 2)
        XCTAssertEqual(d.record(allZero: false, at: 2.5), .signal)
        XCTAssertEqual(d.record(allZero: true, at: 5.4), .signal)      // only 2.9 s since the last signal
        XCTAssertEqual(d.record(allZero: true, at: 5.5), .silent)
        XCTAssertEqual(d.record(allZero: false, at: 6), .signal)
    }

    func testStalledCaptureCountsAsSilentViaTick() {
        var d = SilenceDetector(threshold: 3, startingAt: 0)
        XCTAssertEqual(d.tick(at: 2), .signal)
        XCTAssertEqual(d.tick(at: 3), .silent)
        d.record(allZero: false, at: 3.1)
        XCTAssertEqual(d.verdict, .signal)
    }

    func testHealthyCaptureNeverTripsViaTick() {
        var d = SilenceDetector(threshold: 3, startingAt: 0)
        for t in stride(from: 0.0, to: 60, by: 0.5) {
            d.record(allZero: false, at: t)
            XCTAssertEqual(d.tick(at: t + 0.1), .signal)
        }
    }

    func testResetRestartsTheWindow() {
        var d = SilenceDetector(threshold: 3, startingAt: 0)
        d.tick(at: 5)
        d.reset(at: 10)
        XCTAssertEqual(d.tick(at: 12), .signal)
    }
}

final class CaptureStateMachineTests: XCTestCase {
    func testHappyPath() {
        var m = CaptureStateMachine()
        let g = m.beginStart()
        XCTAssertNotNil(g)
        XCTAssertEqual(m.state, .starting)
        XCTAssertTrue(m.finishStart(generation: g!))
        XCTAssertEqual(m.state, .capturing)
        XCTAssertTrue(m.apply(.silent)); XCTAssertEqual(m.state, .noSignal)
        XCTAssertFalse(m.apply(.silent))
        XCTAssertTrue(m.apply(.signal)); XCTAssertEqual(m.state, .capturing)
        XCTAssertTrue(m.stop()); XCTAssertEqual(m.state, .stopped)
        XCTAssertFalse(m.stop())
    }

    func testStartIsIdempotentWhileRunning() {
        var m = CaptureStateMachine()
        let g = m.beginStart()!
        XCTAssertNil(m.beginStart())
        _ = m.finishStart(generation: g)
        XCTAssertNil(m.beginStart())
        _ = m.apply(.silent)
        XCTAssertNil(m.beginStart())
    }

    func testStopDuringStartCancelsIt() {
        var m = CaptureStateMachine()
        let g = m.beginStart()!
        _ = m.stop()
        XCTAssertFalse(m.finishStart(generation: g))
        XCTAssertFalse(m.failStart(generation: g, as: .failed("late")))
        XCTAssertEqual(m.state, .stopped)
    }

    func testRetryAllowedAfterFailureAndPermissionDenied() {
        for end in [SystemAudioCapture.State.failed("x"), .permissionDenied] {
            var m = CaptureStateMachine()
            let g = m.beginStart()!
            XCTAssertTrue(m.failStart(generation: g, as: end))
            XCTAssertNotNil(m.beginStart())
        }
    }

    func testBackendFailureIgnoredOnceStopped() {
        var m = CaptureStateMachine()
        let g = m.beginStart()!; _ = m.finishStart(generation: g)
        XCTAssertTrue(m.backendFailed(.failed("boom")))
        XCTAssertEqual(m.state, .failed("boom"))
        _ = m.stop()
        XCTAssertFalse(m.backendFailed(.failed("late")))
        XCTAssertEqual(m.state, .stopped)
    }

    func testSilenceVerdictsOnlyApplyWhileRunning() {
        var m = CaptureStateMachine()
        XCTAssertFalse(m.apply(.silent))
        _ = m.beginStart()
        XCTAssertFalse(m.apply(.silent))
        XCTAssertEqual(m.state, .starting)
    }
}

final class SourceSelectionTests: XCTestCase {
    func testEnumBasics() throws {
        XCTAssertEqual(AudioCaptureSource.default, .systemTap)
        XCTAssertEqual(AudioCaptureSource.allCases, [.systemTap, .screenCapture])
        XCTAssertTrue(AudioCaptureSource.allCases.allSatisfy { !$0.title.isEmpty })
        let data = try JSONEncoder().encode(AudioCaptureSource.allCases)
        XCTAssertEqual(try JSONDecoder().decode([AudioCaptureSource].self, from: data), AudioCaptureSource.allCases)
        XCTAssertEqual(AudioCaptureSource(cliName: "tap"), .systemTap)
        XCTAssertEqual(AudioCaptureSource(cliName: "SCREEN"), .screenCapture)
        XCTAssertNil(AudioCaptureSource(cliName: "mic"))
    }

    func testBackendSelection() {
        // Constructing a backend object creates nothing in the system until start().
        XCTAssertTrue(SystemAudioCapture.makeBackend(for: .screenCapture) is ScreenCaptureBackend)
        if #available(macOS 14.2, *) {
            XCTAssertTrue(SystemAudioCapture.makeBackend(for: .systemTap) is ProcessTapBackend)
        }
        XCTAssertEqual(SystemAudioCapture().source, .systemTap)
        XCTAssertEqual(SystemAudioCapture(source: .screenCapture).source, .screenCapture)
    }

    func testPrivacyURL() {
        XCTAssertEqual(SystemAudioCapture.privacySettingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
    }
}

/// Drives `SystemAudioCapture` end to end with a fake backend and a fake clock.
final class SystemAudioCaptureFlowTests: XCTestCase {
    final class FakeBackend: AudioCaptureBackend, @unchecked Sendable {
        var rate = 44_100.0
        var startError: Error?
        var starts = 0, stops = 0
        weak var sink: AudioCaptureSink?
        func start(sink: AudioCaptureSink) async throws -> Double {
            starts += 1
            if let startError { throw startError }
            self.sink = sink
            return rate
        }
        func stop() async { stops += 1 }
    }

    final class Clock: @unchecked Sendable { var now = 100.0 }

    private func make(_ backend: FakeBackend, clock: Clock) -> (SystemAudioCapture, StateLog) {
        let capture = SystemAudioCapture(backend: backend, silenceThreshold: 3, clock: { clock.now })
        let log = StateLog()
        capture.onStateChange = { log.add($0) }
        return (capture, log)
    }

    final class StateLog: @unchecked Sendable {
        private let lock = NSLock(); private var items: [SystemAudioCapture.State] = []
        func add(_ s: SystemAudioCapture.State) { lock.withLock { items.append(s) } }
        var all: [SystemAudioCapture.State] { lock.withLock { items } }
    }

    func testStartUsesBackendRateAndReportsTransitions() async {
        let backend = FakeBackend(), clock = Clock()
        let (capture, log) = make(backend, clock: clock)
        await capture.start()
        XCTAssertEqual(capture.state, .capturing)
        XCTAssertEqual(capture.tracker.sampleRate, 44_100)
        await capture.start()                         // idempotent
        XCTAssertEqual(backend.starts, 1)

        capture.backend(didProduce: [0, 0], allZero: true)
        clock.now += 2.9; capture.backend(didProduce: [0, 0], allZero: true)
        XCTAssertEqual(capture.state, .capturing)
        clock.now += 0.2; capture.backend(didProduce: [0, 0], allZero: true)
        XCTAssertEqual(capture.state, .noSignal)
        clock.now += 1; capture.backend(didProduce: [0.1, -0.1], allZero: false)
        XCTAssertEqual(capture.state, .capturing)

        await capture.stop(); await capture.stop()
        XCTAssertEqual(capture.state, .stopped)
        XCTAssertEqual(log.all, [.starting, .capturing, .noSignal, .capturing, .stopped])
        XCTAssertEqual(backend.stops, 2)              // one per stop() call; the backend makes repeats harmless
    }

    func testWatchdogCatchesAStalledCapture() async {
        let backend = FakeBackend(), clock = Clock()
        let (capture, _) = make(backend, clock: clock)
        await capture.start()
        clock.now += 3.5
        capture.tickSilence()
        XCTAssertEqual(capture.state, .noSignal)
        await capture.stop()
    }

    func testPermissionAndOtherErrors() async {
        let clock = Clock()
        let denied = FakeBackend(); denied.startError = AudioCaptureError.permissionDenied
        let (a, _) = make(denied, clock: clock)
        await a.start()
        XCTAssertEqual(a.state, .permissionDenied)

        let broken = FakeBackend(); broken.startError = AudioCaptureError.failed("no device")
        let (b, _) = make(broken, clock: clock)
        await b.start()
        XCTAssertEqual(b.state, .failed("no device"))
        broken.startError = nil
        await b.start()                                // retry after failure works
        XCTAssertEqual(b.state, .capturing)
        await b.stop()
    }

    func testBackendFailureWhileRunningAndRateChange() async {
        let backend = FakeBackend(), clock = Clock()
        let (capture, log) = make(backend, clock: clock)
        await capture.start()
        capture.backend(didChangeSampleRate: 96_000)
        XCTAssertEqual(capture.tracker.sampleRate, 96_000)
        XCTAssertEqual(capture.state, .capturing)
        capture.backend(didFail: .failed("device gone"))
        XCTAssertEqual(capture.state, .failed("device gone"))
        XCTAssertEqual(log.all.last, .failed("device gone"))
        await capture.stop()
        capture.backend(didFail: .failed("late"))
        XCTAssertEqual(capture.state, .stopped)
    }

    func testTrackerReceivesSamples() async {
        let backend = FakeBackend(), clock = Clock()
        let (capture, _) = make(backend, clock: clock)
        await capture.start()
        let tone = (0..<48_000).map { 0.5 * Float(sin(2 * Double.pi * 60 * Double($0) / 44_100)) }
        capture.backend(didProduce: tone, allZero: false)
        XCTAssertGreaterThan(capture.tracker.features().level, 0)
        await capture.stop()
    }
}

/// Needs a real tap, which makes macOS show the audio recording prompt, so it only runs when
/// explicitly requested: `LYRA_LIVE_TAP_TEST=1 swift test --filter LiveTapLeakTests`.
final class LiveTapLeakTests: XCTestCase {
    func testStartStopLoopLeaksNoDevices() async throws {
        guard ProcessInfo.processInfo.environment["LYRA_LIVE_TAP_TEST"] == "1" else {
            throw XCTSkip("creates a real process tap (privacy prompt); set LYRA_LIVE_TAP_TEST=1 to run")
        }
        let before = AudioDeviceInventory.deviceCount()
        let capture = SystemAudioCapture(source: .systemTap)
        for _ in 0..<50 {
            await capture.start()
            await capture.stop()
        }
        XCTAssertEqual(AudioDeviceInventory.deviceCount(), before)
    }
}
