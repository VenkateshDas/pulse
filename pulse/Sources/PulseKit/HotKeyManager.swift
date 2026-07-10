import Carbon.HIToolbox
import AppKit

/// Registers global hotkeys via Carbon's `RegisterEventHotKey`/
/// `InstallEventHandler` — the same mechanism apps like Rectangle use. No
/// extra permission is required (unlike `CGEventTap`/`NSEvent`'s global
/// monitor, which need Input Monitoring/Accessibility).
///
/// Business logic is registered once per `PulseAction` via `setHandler`;
/// `reregisterAll()` re-reads `KeybindingStore` and re-applies Carbon
/// registrations, so callers never touch Carbon directly.
@MainActor
public final class HotKeyManager {
    public static let shared = HotKeyManager()

    private var actionHandlers: [PulseAction: () -> Void] = [:]
    private var hotKeyRefs: [PulseAction: EventHotKeyRef] = [:]
    private var callbackHandlers: [UInt32: () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?

    private static let signature: OSType = 0x50554C53  // 'PULS'

    private init() {
        installEventHandler()
    }

    /// Registers the closure that runs when `action`'s hotkey fires, then
    /// applies its current binding immediately.
    public func setHandler(_ handler: @escaping () -> Void, for action: PulseAction) {
        actionHandlers[action] = handler
        reregister(action)
    }

    /// Re-applies every action's Carbon registration from the current
    /// `KeybindingStore` state. Call after any rebind, enable/disable, or
    /// reset.
    public func reregisterAll() {
        for action in PulseAction.allCases { reregister(action) }
    }

    private func reregister(_ action: PulseAction) {
        unregister(action)
        guard KeybindingStore.shared.isEnabled(action), let handler = actionHandlers[action] else { return }
        let combo = KeybindingStore.shared.combo(for: action)
        callbackHandlers[action.hotKeyID] = handler
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.hotKeyID)
        let status = RegisterEventHotKey(
            combo.keyCode, combo.carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { hotKeyRefs[action] = ref }
    }

    private func unregister(_ action: PulseAction) {
        if let ref = hotKeyRefs.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
        callbackHandlers[action.hotKeyID] = nil
    }

    fileprivate func fire(_ id: UInt32) {
        callbackHandlers[id]?()
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, _ -> OSStatus in
            guard let eventRef else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            Task { @MainActor in HotKeyManager.shared.fire(id) }
            return noErr
        }, 1, &eventType, nil, &eventHandlerRef)
    }
}
