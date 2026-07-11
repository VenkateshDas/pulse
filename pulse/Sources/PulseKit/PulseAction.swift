import Carbon.HIToolbox

/// The 6 bindable global-hotkey actions, surfaced in Settings ▸ Keyboard
/// Shortcuts. Default combos share a `⌃⌥⌘` prefix to minimize collisions
/// with other apps and macOS system shortcuts.
public enum PulseAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case optimize
    case emptyTrash
    case syncBrightness
    case toggleKeepAwake
    case toggleMenuBarChevron
    case runSpeedTest

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .optimize: "Optimize"
        case .emptyTrash: "Empty Trash"
        case .syncBrightness: "Sync Brightness"
        case .toggleKeepAwake: "Toggle Keep Awake"
        case .toggleMenuBarChevron: "Toggle Menu Bar Chevron"
        case .runSpeedTest: "Run Speed Test"
        }
    }

    public var detail: String {
        switch self {
        case .optimize: "Runs safe optimization tasks."
        case .emptyTrash: "Empties the Trash (with confirmation)."
        case .syncBrightness: "Toggles adaptive brightness sync across displays."
        case .toggleKeepAwake: "Turns Keep Awake on or off."
        case .toggleMenuBarChevron: "Collapses or expands hidden menu-bar icons."
        case .runSpeedTest: "Measures internet speed (~20 s) and notifies with the result."
        }
    }

    public var symbolName: String {
        switch self {
        case .optimize: "bolt.heart.fill"
        case .emptyTrash: "trash"
        case .syncBrightness: "sun.max.fill"
        case .toggleKeepAwake: "cup.and.saucer.fill"
        case .toggleMenuBarChevron: "menubar.rectangle"
        case .runSpeedTest: "gauge.with.needle"
        }
    }

    public var defaultCombo: KeyCombo {
        let prefix = UInt32(controlKey | optionKey | cmdKey)
        switch self {
        case .optimize: return KeyCombo(keyCode: UInt32(kVK_ANSI_O), carbonModifiers: prefix)
        case .emptyTrash: return KeyCombo(keyCode: UInt32(kVK_ANSI_T), carbonModifiers: prefix)
        case .syncBrightness: return KeyCombo(keyCode: UInt32(kVK_ANSI_B), carbonModifiers: prefix)
        case .toggleKeepAwake: return KeyCombo(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: prefix)
        case .toggleMenuBarChevron: return KeyCombo(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: prefix)
        case .runSpeedTest: return KeyCombo(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: prefix)
        }
    }

    /// Stable per-action id used as Carbon's `EventHotKeyID.id` for dispatch.
    var hotKeyID: UInt32 {
        switch self {
        case .optimize: 1
        case .emptyTrash: 2
        case .syncBrightness: 3
        case .toggleKeepAwake: 4
        case .toggleMenuBarChevron: 6
        case .runSpeedTest: 7
        }
    }
}
