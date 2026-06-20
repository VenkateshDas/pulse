import SwiftUI

struct DiskView: View {
    @State private var selectedTab = 0
    @State private var hoveredTab: Int?

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            ZStack {
                if selectedTab == 0 {
                    StorageView()
                } else if selectedTab == 1 {
                    InsightsView()
                } else if selectedTab == 2 {
                    CleanView()
                } else if selectedTab == 3 {
                    TrashView()
                } else if selectedTab == 4 {
                    OptimizeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Halo.Motion.smooth, value: selectedTab)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            tabBtn("Map", index: 0)
            tabBtn("Hidden Space", index: 1)
            tabBtn("Reclaim", index: 2)
            tabBtn("Trash", index: 3)
            tabBtn("Optimize", index: 4)
            Spacer()
        }
        .padding(.horizontal, Halo.Space.xxl)
        .padding(.top, Halo.Space.xl)
        .padding(.bottom, Halo.Space.lg)
        .background { ZStack { Halo.void; Halo.meshBackground } }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Halo.borderSubtle).frame(height: 1)
        }
    }

    private func tabBtn(_ title: String, index: Int) -> some View {
        let isSelected = selectedTab == index
        let isHovered = hoveredTab == index
        return Button {
            withAnimation(Halo.Motion.snappy) { selectedTab = index }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Halo.interactive : (isHovered ? Halo.textPrimary : Halo.textSecondary))
                .padding(.horizontal, Halo.Space.md)
                .padding(.vertical, Halo.Space.sm)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Halo.interactive.opacity(0.10))
                    } else if isHovered {
                        Capsule()
                            .fill(Halo.surface2.opacity(0.5))
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredTab = hovering ? index : nil
            }
        }
    }
}
