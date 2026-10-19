import AppKit
import SwiftUI

// MARK: - Feedback badge

/// Operation feedback ("Sent Quit to X", "Freed 1.2 GB") in a soft green
/// capsule — one look for every action result instead of scattered plain text.
struct FeedbackBadge: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle")
            .font(Halo.font(size: 13))
            .foregroundStyle(Halo.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Halo.surface2, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Process icon cache

/// App icons for process rows, cached by PID. GUI apps resolve via
/// NSRunningApplication; daemons fall back to the generic executable icon.
@MainActor
enum ProcessIconCache {
    private static var cache: [Int32: NSImage] = [:]
    private static let fallback: NSImage = {
        let icon = NSWorkspace.shared.icon(for: .unixExecutable)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }()

    static func icon(for pid: Int32) -> NSImage {
        if let hit = cache[pid] { return hit }
        // ponytail: unbounded PID churn — reset wholesale past 512 entries.
        if cache.count > 512 { cache.removeAll(keepingCapacity: true) }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon ?? fallback
        icon.size = NSSize(width: 16, height: 16)
        cache[pid] = icon
        return icon
    }
}

// MARK: - Refresh button

/// Small header refresh control, shared by every page that shows cached
/// scan data (live-sampled pages update themselves and don't need one).
struct RefreshButton: View {
    let help: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(Halo.font(size: 13, weight: .semibold))
                .padding(4)
        }
        .buttonStyle(.bordered)
        .foregroundStyle(Halo.textDim)
        .help(help)
        .accessibilityLabel(help)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

// MARK: - Page header

/// Shared page heading: calm typography and readable subtitle with optional
/// trailing accessory (buttons, totals). Every full page uses this so titles
/// never drift in size or weight again.
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    init(
        _ title: String, subtitle: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Halo.Space.lg) {
                heading
                Spacer(minLength: 16)
                trailing
            }
            VStack(alignment: .leading, spacing: 12) {
                heading
                trailing
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Halo.font(size: 28, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(Halo.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(Halo.font(size: 14))
                .foregroundStyle(Halo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Segment picker

/// Unified capsule segment control. `.tab` is the large page-level variant
/// (tinted background, 13pt); `.chip` is the compact filled variant (10pt
/// bold caps) used inside cards. Replaces the five hand-rolled versions.
struct SegmentPicker<T: Hashable>: View {
    enum Style { case tab, chip }

    let options: [(value: T, label: String)]
    @Binding var selection: T
    var style: Style = .chip
    var help: ((T) -> String)? = nil

    var body: some View {
        Picker("View options", selection: $selection) {
            ForEach(options, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .font(Halo.font(size: 13))
        .help(help?(selection) ?? "Choose a view")
    }
}

// MARK: - Empty state

/// Shared empty/placeholder state: dim icon, title, optional hint. Fills its
/// container and centers.
struct EmptyState: View {
    let icon: String
    let title: String
    var hint: String? = nil
    var tint: Color = Halo.textDim

    var body: some View {
        VStack(spacing: Halo.Space.md) {
            Image(systemName: icon)
                .font(Halo.font(size: 32))
                .foregroundStyle(tint)
            Text(title)
                .font(Halo.font(size: 14, weight: .medium))
                .foregroundStyle(Halo.textPrimary)
            if let hint {
                Text(hint)
                    .font(Halo.font(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Halo.Space.xl)
    }
}

/// A recognizable task with its purpose and one destination; never executes removal.
struct TaskRow: View {
    let title: String
    let detail: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(Halo.font(size: 18))
                    .foregroundStyle(Halo.interactive)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Halo.font(size: 14, weight: .medium)).foregroundStyle(Halo.textPrimary)
                    Text(detail).font(Halo.font(size: 12)).foregroundStyle(Halo.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").foregroundStyle(Halo.textSecondary).accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
