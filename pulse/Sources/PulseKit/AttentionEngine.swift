import Foundation

/// User-tunable knobs for the Attention system: how many items surface at
/// once, and how long a one-tap "Snooze" hides an item for.
public enum AttentionPreferences {
    private static let maxItemsKey = "PulseMaxAttentionItems"
    private static let snoozeDurationKey = "PulseDefaultSnoozeDuration"

    public static var maxItems: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: maxItemsKey)
            return value == 0 ? 3 : value
        }
        set { UserDefaults.standard.set(newValue, forKey: maxItemsKey) }
    }

    public static var defaultSnoozeDuration: TimeInterval {
        get {
            let value = UserDefaults.standard.double(forKey: snoozeDurationKey)
            return value == 0 ? 3600 : value
        }
        set { UserDefaults.standard.set(newValue, forKey: snoozeDurationKey) }
    }
}

/// One thing worth surfacing on the Dashboard hero or menu-bar HUD: what's
/// wrong, why, and (optionally) a single action that fixes it.
public struct AttentionItem: Identifiable, Sendable, Equatable {
    public enum Severity: String, Sendable, Equatable, Comparable {
        case info, warn, critical

        private var rank: Int {
            switch self {
            case .info: return 0
            case .warn: return 1
            case .critical: return 2
            }
        }
        public static func < (l: Severity, r: Severity) -> Bool { l.rank < r.rank }
    }

    /// Stable across ticks — used for snooze/dismiss and SwiftUI identity.
    public let id: String
    /// e.g. "Chrome using 6.2 GB RAM"
    public let title: String
    /// e.g. "Highest memory user, 40 tabs open"
    public let detail: String
    public let severity: Severity
    /// nil = informational only, no button.
    public let action: AttentionAction?
    public let snoozable: Bool

    public init(
        id: String, title: String, detail: String, severity: Severity,
        action: AttentionAction?, snoozable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
        self.action = action
        self.snoozable = snoozable
    }
}

/// Where an "openPane" action should navigate. Kept decoupled from the app
/// target's `SidebarItem` — PulseKit doesn't depend on Pulse — the app layer
/// maps this onto the real sidebar selection via its existing notifications.
public enum AttentionTarget: String, Sendable, Equatable {
    case monitor, storage
}

public enum AttentionAction: Sendable, Equatable {
    case quitProcess(pid: Int32, name: String)
    case cleanJunk
    case openPane(AttentionTarget)
}

/// Aggregates `DiagnosisEngine` + `AlertsEngine` output into a small ranked
/// list of actionable items. Does not sample anything new — the caller
/// (DashboardModel) already runs both engines every tick; this only ranks,
/// dedupes overlapping causes, and filters out what's snoozed.
public actor AttentionEngine {
    private let snoozeStore: SnoozeStore

    public init(snoozeStore: SnoozeStore = SnoozeStore()) {
        self.snoozeStore = snoozeStore
    }

    /// Ranked, deduped, snoozed-filtered list — max 3.
    public func currentItems(diagnosis: Diagnosis, alerts: [PulseAlert]) async -> [AttentionItem] {
        var items: [AttentionItem] = []
        for candidate in Self.rank(diagnosis: diagnosis, alerts: alerts) {
            guard await !snoozeStore.isSnoozed(candidate.id) else { continue }
            items.append(candidate)
            if items.count == AttentionPreferences.maxItems { break }
        }
        return items
    }

    public func snooze(_ id: String, until: Date) async {
        await snoozeStore.snooze(id, until: until)
    }

    // MARK: - Ranking (pure, testable without the actor)

    /// Alert id that would explain the same underlying cause as this factor.
    private static func matchingAlertID(for factor: HealthFactor) -> String? {
        switch factor {
        case .cpu: return "cpu-hog"
        case .memory: return "memory-pressure"
        case .disk: return "low-disk"
        case .thermal: return "thermal"
        case .diskIO: return nil
        }
    }

    /// Diagnosis first (mole's cpu>memory>disk>thermal cascade), folding in
    /// alerts that share a cause; then remaining alerts by severity.
    static func rank(diagnosis: Diagnosis, alerts: [PulseAlert]) -> [AttentionItem] {
        var items: [AttentionItem] = []
        var consumed: Set<String> = []

        if diagnosis.severity != .clear {
            let matchID = diagnosis.factor.flatMap(matchingAlertID(for:))
            if let matchID, let alert = alerts.first(where: { $0.id == matchID }) {
                items.append(item(from: alert))
                consumed.insert(alert.id)
            } else {
                items.append(item(fromDiagnosisOnly: diagnosis))
            }
        }

        let rest = alerts
            .filter { !consumed.contains($0.id) }
            .sorted { severityRank($0.severity) > severityRank($1.severity) }
        for alert in rest {
            items.append(item(from: alert))
        }

        return Array(items.prefix(AttentionPreferences.maxItems))
    }

    private static func severityRank(_ s: PulseAlert.Severity) -> Int {
        switch s {
        case .info: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    private static func severity(from s: PulseAlert.Severity) -> AttentionItem.Severity {
        switch s {
        case .info: return .info
        case .warning: return .warn
        case .critical: return .critical
        }
    }

    private static func severity(from s: Diagnosis.Severity) -> AttentionItem.Severity {
        switch s {
        case .clear, .info: return .info
        case .warn: return .warn
        case .critical: return .critical
        }
    }

    /// Panes that make sense for a "Review" action on alerts with no direct
    /// fix — cpu/memory/thermal point at Monitor (top processes), disk at
    /// Storage (Clean).
    private static func reviewTarget(for alertID: String) -> AttentionTarget? {
        switch alertID {
        case "cpu-hog", "memory-pressure", "thermal": return .monitor
        case "low-disk": return .storage
        default: return nil
        }
    }

    private static func item(from alert: PulseAlert) -> AttentionItem {
        let action: AttentionAction?
        if let quit = alert.actions.compactMap({ a -> (pid: Int32, name: String)? in
            if case .quitProcess(let pid, let name) = a { return (pid, name) }
            return nil
        }).first {
            action = .quitProcess(pid: quit.pid, name: quit.name)
        } else if alert.id == "low-disk" {
            action = .cleanJunk
        } else if let target = reviewTarget(for: alert.id) {
            action = .openPane(target)
        } else {
            action = nil
        }

        return AttentionItem(
            id: alert.id,
            title: alert.title,
            detail: alert.subtitle,
            severity: severity(from: alert.severity),
            action: action
        )
    }

    private static func item(fromDiagnosisOnly diagnosis: Diagnosis) -> AttentionItem {
        let action: AttentionAction? =
            switch diagnosis.factor {
            case .cpu, .memory: .openPane(.monitor)
            case .disk: .openPane(.storage)
            default: nil
            }
        return AttentionItem(
            id: "diagnosis-\(diagnosis.factor?.rawValue ?? "general")",
            title: diagnosis.line,
            detail: "Highest-priority signal right now",
            severity: severity(from: diagnosis.severity),
            action: action
        )
    }
}
