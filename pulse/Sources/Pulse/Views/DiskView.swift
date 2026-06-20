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
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToOptimize)) { _ in
            withAnimation(Halo.Motion.snappy) { selectedTab = 4 }
        }
    }

    private var tabBar: some View {
        HStack(spacing: Halo.Space.sm) {
            tabBtn("Map", index: 0)
            tabBtn("Hidden Space", index: 1)
            tabBtn("Reclaim", index: 2)
            tabBtn("Trash", index: 3)
            tabBtn("Optimize", index: 4)
            Spacer()
        }
        .padding(.horizontal, Halo.Space.xxl + 8)
        .padding(.top, Halo.Space.xxl)
        .padding(.bottom, Halo.Space.lg)
        .background { ZStack { Halo.void; Halo.meshBackground } }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Halo.borderSubtle).frame(height: 1)
        }
    }

    private func tabBtn(_ title: String, index: Int) -> some View {
        let isSelected = selectedTab == index
        let isHover = hoveredTab == index && !isSelected
        return Button {
            withAnimation(Halo.Motion.snappy) { selectedTab = index }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Halo.interactive : Halo.textDim)
                .padding(.horizontal, Halo.Space.md)
                .padding(.vertical, Halo.Space.sm)
                .background(
                    isSelected
                        ? Halo.interactive.opacity(0.10)
                        : (isHover ? Halo.surface2.opacity(0.6) : .clear),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .onHover { hoveredTab = $0 ? index : nil }
    }
}
