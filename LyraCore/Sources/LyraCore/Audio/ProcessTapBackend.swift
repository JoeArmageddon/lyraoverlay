import Foundation
import CoreAudio
import AudioToolbox

/// Captures system audio with a Core Audio process tap (macOS 14.2+).
///
/// Call sequence on start (all on `queue`):
///  1. listen for kAudioHardwarePropertyDefaultOutputDevice changes (once per backend)
///  2. read the default output device and its UID
///  3. AudioHardwareCreateProcessTap with a private, unmuted, global stereo mixdown tap that
///     excludes Lyra's own process object
///  4. read kAudioTapPropertyFormat -> the real sample rate
///  5. AudioHardwareCreateAggregateDevice: private, not stacked, main sub-device = the output
///     device, tap list = [tap UID], tap auto-start
///  6. AudioDeviceCreateIOProcIDWithBlock + AudioDeviceStart
///
/// Teardown (stop, deinit, failed start, output device change) always runs in this order:
///  AudioDeviceStop, AudioDeviceDestroyIOProcID, AudioHardwareDestroyAggregateDevice,
///  AudioHardwareDestroyProcessTap, each only for the objects that were actually created.
///
/// Permission: there is no preflight. When System Audio Recording is not allowed the tap
/// delivers zeros, which `SystemAudioCapture` reports as `.noSignal`.
@available(macOS 14.2, *)
final class ProcessTapBackend: AudioCaptureBackend, @unchecked Sendable {
    private let queue = DispatchQueue(label: "lyra.audio-capture.tap", qos: .userInitiated)
    private let ioQueue = DispatchQueue(label: "lyra.audio-capture.tap.io", qos: .userInitiated)

    // Everything below is touched only on `queue`.
    private weak var sink: AudioCaptureSink?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var graphDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var running = false
    private var listener: AudioObjectPropertyListenerBlock?

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    deinit {
        queue.sync {
            teardownGraph()
            removeListener()
        }
    }

    // MARK: - AudioCaptureBackend

    func start(sink: AudioCaptureSink) async throws -> Double {
        try await onQueue {
            self.teardownGraph()
            self.sink = sink
            self.installListener()
            do {
                let rate = try self.buildGraph()
                self.running = true
                return rate
            } catch {
                self.teardownGraph()
                self.removeListener()
                throw error
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async {
                self.running = false
                self.teardownGraph()
                self.removeListener()
                self.sink = nil
                c.resume()
            }
        }
    }

    private func onQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
            queue.async { c.resume(with: Result { try work() }) }
        }
    }

    // MARK: - Build

    private func buildGraph() throws -> Double {
        let outputDevice = try Self.defaultOutputDevice()
        let outputUID = try Self.deviceUID(outputDevice)

        let excluded: [AudioObjectID] = Self.ownProcessObject().map { [$0] } ?? []
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        let tapUUID = UUID()
        description.uuid = tapUUID
        description.name = "Lyra system audio tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTap = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateProcessTap(description, &newTap), "create the audio tap")
        tapID = newTap

        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        try Self.check(AudioObjectGetPropertyData(newTap, &formatAddress, 0, nil, &formatSize, &format), "read the tap format")
        let rate = format.mSampleRate > 0 ? format.mSampleRate : 48_000

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Lyra audio tap",
            kAudioAggregateDeviceUIDKey: "app.lyra.mac.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapUUID.uuidString,
            ]],
        ]
        var newAggregate = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &newAggregate), "create the aggregate device")
        aggregateID = newAggregate

        // The IO block runs on ioQueue; it only touches its own scratch buffer and a weak sink.
        var scratch: [Float] = []
        scratch.reserveCapacity(4096)
        let weakSink = WeakSink(sink)
        var newProc: AudioDeviceIOProcID?
        try Self.check(AudioDeviceCreateIOProcIDWithBlock(&newProc, newAggregate, ioQueue) { _, inputData, _, _, _ in
            let result = AudioSampleConversion.mono(from: inputData, into: &scratch)
            guard result.frames > 0, let sink = weakSink.sink else { return }
            sink.backend(didProduce: scratch, allZero: result.allZero)
        }, "create the IO proc")
        procID = newProc
        try Self.check(AudioDeviceStart(newAggregate, newProc), "start the tap")
        graphDeviceID = outputDevice
        return rate
    }

    // MARK: - Teardown (idempotent; order matters)

    private func teardownGraph() {
        if aggregateID != kAudioObjectUnknown, let proc = procID {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        graphDeviceID = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: - Default output device changes

    private func installListener() {
        guard listener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.defaultOutputChanged() }
        listener = block
        var address = Self.defaultOutputAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
    }

    private func removeListener() {
        guard let block = listener else { return }
        var address = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
        listener = nil
    }

    /// Runs on `queue`. Headphones, AirPlay, a display speaker: the tap is tied to the old
    /// device's clock, so rebuild it on the new one.
    private func defaultOutputChanged() {
        guard running, let sink else { return }
        guard let device = try? Self.defaultOutputDevice(), device != graphDeviceID else { return }
        teardownGraph()
        do {
            let rate = try buildGraph()
            sink.backend(didChangeSampleRate: rate)
        } catch {
            teardownGraph()
            running = false
            sink.backend(didFail: .failed("could not follow the new output device: \(error.localizedDescription)"))
        }
    }

    // MARK: - Core Audio helpers

    private final class WeakSink {
        weak var sink: AudioCaptureSink?
        init(_ sink: AudioCaptureSink?) { self.sink = sink }
    }

    private static func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else {
            throw AudioCaptureError.failed("could not \(what) (Core Audio error \(fourCC(status)))")
        }
    }

    static func fourCC(_ status: OSStatus) -> String {
        let n = UInt32(bitPattern: status)
        let bytes = [UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
        if bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) { return "'\(String(decoding: bytes, as: UTF8.self))'" }
        return String(status)
    }

    private static func defaultOutputDevice() throws -> AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = defaultOutputAddress
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device), "find the output device")
        guard device != kAudioObjectUnknown else { throw AudioCaptureError.failed("there is no audio output device") }
        return device
    }

    private static func deviceUID(_ device: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &ref), "read the output device UID")
        guard let ref else { throw AudioCaptureError.failed("the output device has no UID") }
        return ref.takeRetainedValue() as String
    }

    /// Lyra's own audio process object, so the tap never hears Lyra. nil when Lyra has not
    /// played audio (then there is nothing of ours to exclude).
    private static func ownProcessObject() -> AudioObjectID? {
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }
}

/// Counts every audio device the HAL lists, aggregates included. Used by the guarded leak test.
enum AudioDeviceInventory {
    static func deviceCount() -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return -1 }
        return Int(size) / MemoryLayout<AudioObjectID>.size
    }
}
