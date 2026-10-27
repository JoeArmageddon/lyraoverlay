import Foundation
import AudioToolbox

/// Pure helpers that turn Core Audio buffers into the mono Float stream the analyzer wants.
enum AudioSampleConversion {
    /// Averages every channel of every buffer into one mono array and reports whether every
    /// sample was exactly 0.0 (digital silence).
    ///
    /// Works for interleaved (one buffer, N channels), planar (N buffers, one channel each),
    /// mixed layouts and any channel count, because each `AudioBuffer` states its own
    /// `mNumberChannels`. Only 32-bit float samples are supported (what taps and SCK deliver).
    /// Buffers shorter than the first are ignored for the missing tail, never read past their end.
    static func mono(from list: UnsafePointer<AudioBufferList>, into out: inout [Float]) -> (frames: Int, allZero: Bool) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        return mono(from: buffers.map { ($0.mData, Int($0.mDataByteSize), max(1, Int($0.mNumberChannels))) }, into: &out)
    }

    static func mono(from buffers: [(data: UnsafeMutableRawPointer?, byteSize: Int, channels: Int)],
                     into out: inout [Float]) -> (frames: Int, allZero: Bool) {
        let usable = buffers.filter { $0.data != nil && $0.byteSize >= MemoryLayout<Float>.size * max(1, $0.channels) }
        let stride = MemoryLayout<Float>.size
        guard let frames = usable.map({ $0.byteSize / (stride * $0.channels) }).min(), frames > 0 else {
            out.removeAll(keepingCapacity: true)
            return (0, true)
        }
        let totalChannels = usable.reduce(0) { $0 + $1.channels }
        out.removeAll(keepingCapacity: true)
        out.append(contentsOf: repeatElement(0, count: frames))
        var allZero = true
        out.withUnsafeMutableBufferPointer { dst in
            for buffer in usable {
                let src = buffer.data!.assumingMemoryBound(to: Float.self)
                let channels = buffer.channels
                for f in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<channels { sum += src[f * channels + c] }
                    dst[f] += sum
                }
            }
            let scale = 1 / Float(totalChannels)
            for f in 0..<frames {
                // NaN/inf from a misbehaving source would poison the analyzer; treat as silence.
                let v = dst[f] * scale
                dst[f] = v.isFinite ? v : 0
                if dst[f] != 0 { allZero = false }
            }
        }
        return (frames, allZero)
    }

    /// Convenience for tests and callers holding plain arrays: `planes` are planar channels,
    /// or pass one array with `interleavedChannels` > 1.
    static func mono(interleaved samples: [Float], channels: Int) -> (samples: [Float], allZero: Bool) {
        var copy = samples
        var out: [Float] = []
        let result = copy.withUnsafeMutableBytes { raw in
            mono(from: [(raw.baseAddress, raw.count, channels)], into: &out)
        }
        return (out, result.allZero)
    }
}
