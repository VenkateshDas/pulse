import Foundation

/// UserDefaults-backed bindings for each `PulseAction`: its current
/// `KeyCombo`, whether it's enabled, and duplicate-combo rejection.
@MainActor
public final class KeybindingStore {
    public static let shared = KeybindingStore()

    private let defaults = UserDefaults.standard

    private init() {}

    private static func comboKey(_ action: PulseAction) -> String { "PulseKeybinding.\(action.rawValue)" }
    private static func enabledKey(_ action: PulseAction) -> String { "PulseKeybindingEnabled.\(action.rawValue)" }

    public func combo(for action: PulseAction) -> KeyCombo {
        guard let data = defaults.data(forKey: Self.comboKey(action)),
              let combo = try? JSONDecoder().decode(KeyCombo.self, from: data)
        else { return action.defaultCombo }
        return combo
    }

    public func isEnabled(_ action: PulseAction) -> Bool {
        defaults.object(forKey: Self.enabledKey(action)) as? Bool ?? true
    }

    public func setEnabled(_ enabled: Bool, for action: PulseAction) {
        defaults.set(enabled, forKey: Self.enabledKey(action))
        HotKeyManager.shared.reregisterAll()
    }

    /// The other enabled action already bound to `combo`, if any.
    public func conflict(for combo: KeyCombo, excluding action: PulseAction) -> PulseAction? {
        PulseAction.allCases.first { other in
            other != action && isEnabled(other) && self.combo(for: other) == combo
        }
    }

    /// Binds `combo` to `action`. Returns the conflicting action (and leaves
    /// the existing binding untouched) if `combo` is already in use.
    @discardableResult
    public func setCombo(_ combo: KeyCombo, for action: PulseAction) -> PulseAction? {
        if let conflict = conflict(for: combo, excluding: action) { return conflict }
        if let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: Self.comboKey(action))
        }
        HotKeyManager.shared.reregisterAll()
        return nil
    }

    public func resetToDefault(_ action: PulseAction) {
        defaults.removeObject(forKey: Self.comboKey(action))
        defaults.removeObject(forKey: Self.enabledKey(action))
        HotKeyManager.shared.reregisterAll()
    }
}
