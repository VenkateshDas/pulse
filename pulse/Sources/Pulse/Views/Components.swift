import AppKit
import SwiftUI

// MARK: - Feedback badge

/// Operation feedback ("Sent Quit to X", "Freed 1.2 GB") in a soft green
/// capsule — one look for every action result instead of scattered plain text.
struct FeedbackBadge: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
        }
        .foregroundStyle(Halo.pulseGreen)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Halo.pulseGreen.opacity(0.10), in: Capsule())
        .transition(.opacity.combined(with: .move(edge: .top)))
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
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Halo.textDim)
        .help(help)
        .accessibilityLabel(help)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

// MARK: - Page header

/// Standard page header: 24pt bold title, dim one-line subtitle, optional
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
        HStack(alignment: .center, spacing: Halo.Space.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Halo.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing
        }
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

    @State private var hovered: T?

    var body: some View {
        HStack(spacing: style == .tab ? Halo.Space.sm : 4) {
            ForEach(options, id: \.value) { option in
                segment(option.value, label: option.label)
            }
        }
    }

    @ViewBuilder
    private func segment(_ value: T, label: String) -> some View {
        let isSelected = selection == value
        let isHover = hovered == value && !isSelected
        Button {
            withAnimation(Halo.Motion.snappy) { selection = value }
        } label: {
            Group {
                switch style {
                case .tab:
                    Text(label)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Halo.interactive : Halo.textDim)
                        .padding(.horizontal, Halo.Space.md)
                        .padding(.vertical, Halo.Space.sm)
                        .background(
                            isSelected
                                ? Halo.interactive.opacity(0.10)
                                : (isHover ? Halo.surface2.opacity(0.6) : .clear),
                            in: Capsule())
                case .chip:
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(isSelected ? Halo.void : Halo.textDim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            isSelected
                                ? AnyShapeStyle(Halo.ion)
                                : AnyShapeStyle(Halo.surface2.opacity(isHover ? 1.0 : 0.75)),
                            in: Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? value : nil }
        .help(help?(value) ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                .font(.system(size: 32))
                .foregroundStyle(tint.opacity(0.55))
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Halo.textPrimary.opacity(0.85))
            if let hint {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Halo.Space.xl)
    }
}
