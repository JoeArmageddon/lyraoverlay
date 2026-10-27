import Foundation
import IOKit.pwr_mgt

/// Something that can hold the Mac awake. A seam so the policy is testable without touching power state.
public protocol PowerAssertion: AnyObject {
    /// Returns whether the assertion is now held. Creating twice must not leak a second one.
    func create(reason: String) -> Bool
    func release()
}

/// A real power assertion: stops the display, and with it the Mac, from sleeping due to inactivity.
public final class IOKitPowerAssertion: PowerAssertion {
    private var id = IOPMAssertionID(0)
    private var held = false

    public init() {}

    public func create(reason: String) -> Bool {
        if held { return true }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)
        held = result == kIOReturnSuccess
        return held
    }

    public func release() {
        guard held else { return }
        IOPMAssertionRelease(id)
        held = false
    }

    deinit { release() }
}

public enum KeepAwakePolicy {
    /// Awake only while it is switched on, the window can be seen and music is playing: a closed,
    /// minimized or paused player has no reason to keep the display lit.
    public static func shouldBeAwake(enabled: Bool, windowVisible: Bool, playing: Bool) -> Bool {
        enabled && windowVisible && playing
    }
}

/// Holds a power assertion exactly while `KeepAwakePolicy` says so. Call `update` as often as
/// convenient; the assertion is created and released only on a change. Main thread only.
public final class KeepAwake {
    private let assertion: PowerAssertion
    public private(set) var isActive = false

    public init(assertion: PowerAssertion = IOKitPowerAssertion()) {
        self.assertion = assertion
    }

    deinit { if isActive { assertion.release() } }

    public func update(enabled: Bool, windowVisible: Bool, playing: Bool) {
        let want = KeepAwakePolicy.shouldBeAwake(enabled: enabled, windowVisible: windowVisible, playing: playing)
        if want, !isActive {
            // If the system refuses, stay inactive and try again on the next update.
            isActive = assertion.create(reason: "Lyra is showing lyrics")
        } else if !want, isActive {
            assertion.release()
            isActive = false
        }
    }

    /// Release now, whatever the policy says (the window is closing).
    public func releaseNow() {
        guard isActive else { return }
        assertion.release()
        isActive = false
    }
}
