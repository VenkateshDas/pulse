import SwiftUI

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
