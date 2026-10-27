import Foundation
import ScreenCaptureKit
import CoreMedia
import AudioToolbox

/// The original ScreenCaptureKit audio-only stream. Needs the broad Screen & System Audio
/// Recording permission and macOS re-prompts for it; kept as an explicit fallback.
final class ScreenCaptureBackend: NSObject, AudioCaptureBackend, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    static let sampleRate = 48_000.0

    private let lock = NSLock()
    private var stream: SCStream?
    private weak var sink: AudioCaptureSink?
    private var scratch: [Float] = []
    private let queue = DispatchQueue(label: "lyra.audio-capture.sck", qos: .userInitiated)

    func start(sink: AudioCaptureSink) async throws -> Double {
        await stop()
        lock.withLock { self.sink = sink }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { throw AudioCaptureError.failed("no display found") }
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = Int(Self.sampleRate)
            config.channelCount = 2
            // We only want audio; make the required video stream as cheap as possible.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            // Some macOS versions only deliver audio when a screen output is attached too.
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "lyra.audio-capture.video", qos: .utility))
            try await stream.startCapture()
            lock.withLock { self.stream = stream }
            return Self.sampleRate
        } catch let error as AudioCaptureError {
            throw error
        } catch {
            let ns = error as NSError
            // -3801: the user declined the screen capture permission.
            if ns.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && ns.code == -3801 {
                throw AudioCaptureError.permissionDenied
            }
            throw AudioCaptureError.failed(ns.localizedDescription)
        }
    }

    func stop() async {
        let current: SCStream? = lock.withLock { let s = stream; stream = nil; return s }
        try? await current?.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let sink = lock.withLock({ self.sink }) else { return }
        var needed = 0
        _ = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &needed, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        guard needed > 0 else { return }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: 16)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: needed,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &block)
        guard status == noErr else { return }
        let result = AudioSampleConversion.mono(from: list, into: &scratch)
        guard result.frames > 0 else { return }
        sink.backend(didProduce: scratch, allZero: result.allZero)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock { self.stream = nil }
        lock.withLock { self.sink }?.backend(didFail: .failed(error.localizedDescription))
    }
}
