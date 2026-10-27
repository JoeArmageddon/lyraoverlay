import Carbon.HIToolbox
import Foundation

/// A system-wide keyboard shortcut: it fires while any app is in front. It uses the Carbon hot key
/// API, which needs no Accessibility or Input Monitoring permission.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: () -> Void
    private let id: UInt32

    private static var nextID: UInt32 = 1
    private static let signature = OSType(0x4C59_5241)   // 'LYRA'

    /// Returns nil when the combination is already taken by another app or the system.
    init?(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        self.handler = handler
        self.id = Self.nextID
        Self.nextID += 1

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            // Every hot key shares the application event target, so each handler checks it is the one pressed.
            if status == noErr, pressed.signature == GlobalHotKey.signature, pressed.id == hotKey.id {
                DispatchQueue.main.async { hotKey.handler() }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard installed == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
