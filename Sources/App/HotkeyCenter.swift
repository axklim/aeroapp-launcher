import Carbon
import Foundation

/// Global hotkeys via Carbon's `RegisterEventHotKey`. A plain chord like ⌥Space
/// needs nothing more — no event tap, no Accessibility permission.
final class HotkeyCenter {
    private struct Registration {
        let hotkey: Hotkey
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    private static let signature: OSType = 0x41414C4E // "AALN"

    private var registrations: [UInt32: Registration] = [:]
    private var nextId: UInt32 = 1
    private var handlerRef: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                return center.handle(event)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        if status != noErr {
            log("cannot install hotkey handler (OSStatus \(status))")
        }
    }

    deinit {
        unregisterAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Registers `hotkey`; returns false (and logs) when the system refuses it.
    @discardableResult
    func register(_ hotkey: Hotkey, action: @escaping () -> Void) -> Bool {
        let id = nextId
        nextId += 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            log("cannot register hotkey \(hotkey) (OSStatus \(status))")
            return false
        }
        registrations[id] = Registration(hotkey: hotkey, ref: ref, action: action)
        return true
    }

    func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == Self.signature,
              let registration = registrations[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }
        registration.action()
        return noErr
    }
}
