import SwiftUI

struct DiskView: View {
    @State private var selectedTab = 0

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
    }
    
    private var tabBar: some View {
        HStack(spacing: 24) {
            tabBtn("Map", index: 0)
            tabBtn("Hidden Space", index: 1)
            tabBtn("Reclaim", index: 2)
            tabBtn("Trash", index: 3)
            tabBtn("Optimize", index: 4)
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .background(Halo.void)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Halo.border).frame(height: 1)
        }
    }
    
    private func tabBtn(_ title: String, index: Int) -> some View {
        Button { selectedTab = index } label: {
            Text(title)
                .font(.system(size: 13, weight: selectedTab == index ? .semibold : .regular))
                .foregroundStyle(selectedTab == index ? Halo.ion : Halo.textDim)
                .padding(.bottom, 16)
                .overlay(alignment: .bottom) {
                    if selectedTab == index {
                        Rectangle()
                            .fill(Halo.ion)
                            .frame(height: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
