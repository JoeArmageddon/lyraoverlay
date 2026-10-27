// Spike: capture system audio (no microphone) with ScreenCaptureKit and derive
// level + a crude onset/beat signal. Play something in Spotify or Music first.
//
// Usage: audio-spike [seconds]

import Foundation
import ScreenCaptureKit
import CoreMedia
import Accelerate

final class Analyzer: NSObject, SCStreamOutput, SCStreamDelegate {
    private var prevEnergy: Float = 0
    private var avgFlux: Float = 0.0001
    private(set) var buffers = 0
    private(set) var beats = 0
    private(set) var peak: Float = 0
    private var lastPrint = Date()

    private(set) var rawCallbacks = 0
    private(set) var audioCallbacks = 0
    private(set) var lastStatus: OSStatus = 0
    private(set) var format = ""

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        rawCallbacks += 1
        guard type == .audio, sb.isValid else { return }
        audioCallbacks += 1

        if format.isEmpty, let fd = sb.formatDescription,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
            format = "\(asbd.mSampleRate) Hz, \(asbd.mChannelsPerFrame) ch, planar=\(asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0)"
        }

        // SCK audio is planar (one buffer per channel), so a single-buffer
        // AudioBufferList is too small. Ask for the required size first.
        var needed = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb, bufferListSizeNeededOut: &needed, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        guard needed > 0 else { lastStatus = status; return }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: 16)
        defer { raw.deallocate() }
        let ablPtr = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb, bufferListSizeNeededOut: nil, bufferListOut: ablPtr, bufferListSize: needed,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &block)
        lastStatus = status
        guard status == noErr else { return }

        // Mix channels by taking the max RMS across buffers.
        var rms: Float = 0
        for buf in UnsafeMutableAudioBufferListPointer(ablPtr) {
            guard let data = buf.mData else { continue }
            let count = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            var r: Float = 0
            vDSP_rmsqv(data.assumingMemoryBound(to: Float.self), 1, &r, vDSP_Length(count))
            rms = max(rms, r)
        }
        buffers += 1
        peak = max(peak, rms)

        // Onset: positive energy flux well above its running average.
        let flux = max(0, rms - prevEnergy)
        prevEnergy = rms
        avgFlux = avgFlux * 0.95 + flux * 0.05
        let isBeat = flux > avgFlux * 3 && rms > 0.01
        if isBeat { beats += 1 }

        if Date().timeIntervalSince(lastPrint) > 0.1 {
            lastPrint = Date()
            let bar = String(repeating: "#", count: min(50, Int(rms * 200)))
            print(String(format: "rms %.4f %@ %@", rms, isBeat ? "BEAT" : "    ", bar))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error)")
    }
}

let seconds = CommandLine.arguments.dropFirst().compactMap(Double.init).first ?? 10

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            print("FAIL: no display found"); exit(1)
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true
        cfg.excludesCurrentProcessAudio = true
        cfg.sampleRate = 48_000
        cfg.channelCount = 2
        // Smallest, slowest video stream we can get; we only want audio.
        cfg.width = 2
        cfg.height = 2
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let analyzer = Analyzer()
        let stream = SCStream(filter: filter, configuration: cfg, delegate: analyzer)
        try stream.addStreamOutput(analyzer, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        // Some macOS versions only deliver audio when a screen output is attached too.
        try stream.addStreamOutput(analyzer, type: .screen, sampleHandlerQueue: .global(qos: .utility))
        try await stream.startCapture()
        print("Capturing system audio for \(Int(seconds))s. Play music now.")
        try await Task.sleep(for: .seconds(seconds))
        try await stream.stopCapture()

        print("""

        --- Result ---
        raw callbacks (any type): \(analyzer.rawCallbacks)
        audio callbacks:          \(analyzer.audioCallbacks)
        last CoreMedia status:    \(analyzer.lastStatus)
        audio format:             \(analyzer.format.isEmpty ? "n/a" : analyzer.format)
        audio buffers processed:  \(analyzer.buffers)
        peak rms:               \(analyzer.peak)
        beats detected:         \(analyzer.beats)
        verdict:                \(analyzer.buffers > 0 ? (analyzer.peak > 0.001 ? "PASS (audio captured)" : "PARTIAL (stream works but silence; was music playing?)") : "FAIL (no audio buffers)")
        """)
        exit(0)
    } catch {
        print("FAIL: \(error)")
        print("If this is a permission error, grant Screen Recording to your terminal in System Settings > Privacy & Security, then re-run.")
        exit(1)
    }
}
RunLoop.main.run()
