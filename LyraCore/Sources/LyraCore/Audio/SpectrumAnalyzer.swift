import Foundation
import Accelerate

/// One analysis window of audio. Magnitudes are in sine-amplitude units: a full-scale
/// sine at one frequency reads about 1.0 in its band.
public struct SpectralFrame: Equatable, Sendable {
    /// Seconds since the analyzer started, at the end of the window.
    public var time: Double
    public var rms: Float
    public var bass: Float      // about 20-150 Hz
    public var mid: Float       // 150 Hz - 2 kHz
    public var treble: Float    // 2 - 12 kHz
    /// Positive change in the compressed spectrum since the previous frame: an onset signal.
    public var flux: Float
    /// 0 (dark, bass-heavy) ... 1 (bright), on a log frequency scale.
    public var centroid: Float
}

/// Short-time FFT over a stream of mono samples. Not thread-safe: feed it from one queue.
public final class SpectrumAnalyzer {
    public let sampleRate: Double
    static let fftSize = 2048   // ~43 ms at 48 kHz, ~23 Hz per bin: enough to separate the bass band
    static let hop = 512        // ~10.7 ms between frames

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private var pending: [Float] = []
    private var previous: [Float]
    private var consumed: Int64 = 0
    private let half = SpectrumAnalyzer.fftSize / 2

    private let bassBins: Range<Int>
    private let midBins: Range<Int>
    private let trebleBins: Range<Int>
    private let fluxBins: Range<Int>
    private let binHz: Double

    public init(sampleRate: Double = 48_000) {
        self.sampleRate = sampleRate
        let n = Self.fftSize
        log2n = vDSP_Length(log2(Double(n)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        var w = [Float](repeating: 0, count: n)
        vDSP_hann_window(&w, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        window = w
        previous = [Float](repeating: 0, count: n / 2)

        binHz = sampleRate / Double(n)
        func bins(_ lo: Double, _ hi: Double) -> Range<Int> {
            let a = max(1, Int((lo / (sampleRate / Double(n))).rounded(.up)))
            let b = min(n / 2, Int((hi / (sampleRate / Double(n))).rounded(.up)))
            return a..<max(a + 1, b)
        }
        bassBins = bins(20, 150)
        midBins = bins(150, 2_000)
        trebleBins = bins(2_000, 12_000)
        fluxBins = bins(30, 5_000)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Consumes samples and returns a frame for every hop completed.
    public func process(_ samples: [Float]) -> [SpectralFrame] {
        pending.append(contentsOf: samples)
        var frames: [SpectralFrame] = []
        let n = Self.fftSize
        while pending.count >= n {
            frames.append(analyze(Array(pending[0..<n]), endSample: consumed + Int64(n)))
            pending.removeFirst(Self.hop)
            consumed += Int64(Self.hop)
        }
        return frames
    }

    public func reset() {
        pending.removeAll()
        previous = [Float](repeating: 0, count: half)
        consumed = 0
    }

    // MARK: - One window

    private func analyze(_ frame: [Float], endSample: Int64) -> SpectralFrame {
        let n = Self.fftSize
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(n))

        var rms: Float = 0
        vDSP_rmsqv(frame, 1, &rms, vDSP_Length(n))

        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                ip.baseAddress![0] = 0   // the Nyquist term is packed into imag[0]
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(half))
            }
        }
        // vDSP's real FFT output is doubled and the normalized Hann window has unit gain,
        // so 1/N makes a unit-amplitude sine read about 1.0.
        var scale = 1 / Float(n)
        vDSP_vsmul(mags, 1, &scale, &mags, 1, vDSP_Length(half))

        // Onset signal: growth of the log-compressed spectrum in the musical range.
        var flux: Float = 0
        for i in fluxBins {
            let now = log1p(mags[i] * 200)
            let before = log1p(previous[i] * 200)
            flux += max(0, now - before)
        }
        previous = mags

        // Centroid in Hz over 50 Hz - 10 kHz, mapped to a log 0...1 scale.
        var weighted: Double = 0, total: Double = 0
        for i in 1..<half {
            let hz = Double(i) * binHz
            guard hz >= 50, hz <= 10_000 else { continue }
            weighted += hz * Double(mags[i])
            total += Double(mags[i])
        }
        var centroid: Float = 0
        if total > 1e-6 {
            centroid = Float(min(1, max(0, log2((weighted / total) / 100) / log2(80))))
        }

        return SpectralFrame(
            time: Double(endSample) / sampleRate, rms: rms,
            bass: bandRMS(mags, bassBins), mid: bandRMS(mags, midBins), treble: bandRMS(mags, trebleBins),
            flux: flux, centroid: centroid)
    }

    private func bandRMS(_ mags: [Float], _ bins: Range<Int>) -> Float {
        var sum: Float = 0
        for i in bins { sum += mags[i] * mags[i] }
        return sqrt(sum)
    }
}
