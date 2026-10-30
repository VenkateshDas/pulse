import Testing
@testable import Pulse

@Suite("Task navigation")
struct SidebarVisibilityTests {
    @Test func arrowNavigationCoversEveryDestinationAndStopsAtEdges() {
        let items = SidebarItem.navigationOrder
        #expect(Set(items) == Set(SidebarItem.allCases))
        for pair in zip(items, items.dropFirst()) {
            #expect(SidebarItem.adjacent(to: pair.0, offset: 1) == pair.1)
            #expect(SidebarItem.adjacent(to: pair.1, offset: -1) == pair.0)
        }
        #expect(SidebarItem.adjacent(to: items[0], offset: -1) == items[0])
        #expect(SidebarItem.adjacent(to: items[items.count - 1], offset: 1) == items[items.count - 1])
    }

    @Test func everyDestinationIsReachable() {
        let destinations = SidebarItem.everyday + SidebarItem.advanced + [.settings]
        #expect(Set(destinations) == Set(SidebarItem.allCases))
        #expect(Set(destinations).count == destinations.count)
    }

    @Test func removedAssistantRouteIsUnavailable() {
        #expect(SidebarItem(rawValue: "Agent") == nil)
    }

    @Test func shortcutsKeepTheirOriginalDestinations() {
        #expect(Array(SidebarItem.allCases.prefix(8)) == [.dashboard, .storage, .timeline, .optimize, .uninstall, .monitor, .network, .displays])
        #expect(SidebarItem(rawValue: "Dashboard") == .dashboard)
        #expect(SidebarItem(rawValue: "Uninstall") == .uninstall)
    }

    @Test func navigationGroupsHaveNoDuplicates() {
        #expect(Set(SidebarItem.everyday).isDisjoint(with: SidebarItem.advanced))
        #expect(SidebarItem.advanced.contains(.startup))
        #expect(SidebarItem.advanced.contains(.benchmark))
    }
}

@Suite("Plain status")
struct SidebarStatusTextTests {
    @Test func severityTakesPrecedenceInEveryDetailPreference() {
        for mode in DisplayMode.allCases {
            #expect(SidebarView.statusText(mode: mode, hasCritical: true, hasWarning: true) == "Needs attention")
            #expect(SidebarView.statusText(mode: mode, hasCritical: false, hasWarning: true) == "Something to review")
            #expect(SidebarView.statusText(mode: mode, hasCritical: false, hasWarning: false) == "No urgent issues detected")
        }
    }
}

@Suite("Contextual navigation")
@MainActor
struct ContextualNavigationTests {
    @Test func routeSurvivesBeforeWindowAppearsAndIsConsumedOnce() {
        _ = PulseNavigation.takePending()
        PulseNavigation.open(.storage, diskTab: 1)
        let route = PulseNavigation.takePending()
        #expect(route?.destination == .storage)
        #expect(route?.diskTab == 1)
        #expect(PulseNavigation.takePending() == nil)
    }
}
