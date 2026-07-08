import SwiftUI

struct DiskView: View {
    @Environment(StorageModel.self) private var storage
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            ZStack {
                if selectedTab == 0 {
                    StorageView()
                } else if selectedTab == 1 {
                    CleanView()
                } else if selectedTab == 2 {
                    TrashView()
                } else if selectedTab == 3 {
                    GrowthView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Already-visible case: the notification arrives while this view lives.
        .onReceive(NotificationCenter.default.publisher(for: TimelineView.navigateToClean)) { _ in
            open(tab: 1)
        }
        // Cross-pane case: RootView stashed the target tab before this view existed.
        .onAppear {
            if let tab = storage.pendingDiskTab { open(tab: tab) }
        }
    }

    private func open(tab: Int) {
        storage.pendingDiskTab = nil
        withAnimation(Halo.Motion.snappy) { selectedTab = tab }
    }

    private var tabBar: some View {
        HStack {
            SegmentPicker(
                options: [(0, "Browse"), (1, "Reclaim"), (2, "Trash"), (3, "Growth")],
                selection: $selectedTab,
                style: .tab)
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
}
