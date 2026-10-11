import SwiftUI

struct DiskView: View {
    @Environment(StorageModel.self) private var storage
    @State private var selectedTab = 1

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
                } else if selectedTab == 4 {
                    DuplicateView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Already-visible case: the notification arrives while this view lives.
        .onReceive(NotificationCenter.default.publisher(for: TimelineView.navigateToClean)) { _ in
            open(tab: 1)
        }
        // Cross-pane case: RootView stashed the target tab before this view existed.
        .onChange(of: storage.pendingDiskTab) { _, tab in
            if let tab { open(tab: tab) }
        }
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
                options: [(1, "Cleanup"), (0, "Files"), (4, "Duplicates"), (3, "Changes"), (2, "Trash")],
                selection: $selectedTab,
                style: .tab)
            Spacer()
        }
        .padding(.horizontal, Halo.Space.xxl + 8)
        .padding(.top, Halo.Space.xxl)
        .padding(.bottom, Halo.Space.lg)
        .background(Halo.void)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Halo.borderSubtle).frame(height: 1)
        }
    }
}
