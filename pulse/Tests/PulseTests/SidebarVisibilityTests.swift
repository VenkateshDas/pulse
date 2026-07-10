import Testing

@testable import Pulse

@Suite("Sidebar visibility")
struct SidebarVisibilityTests {
    @Test func proModeShowsEveryItemInEverySection() {
        for section in SidebarSection.allCases {
            #expect(section.visibleItems(for: .pro) == section.items)
        }
    }

    @Test func simpleModeHidesAdvancedItemsFromTopLevelRows() {
        let systemVisible = SidebarSection.system.visibleItems(for: .simple)
        let toolsVisible = SidebarSection.tools.visibleItems(for: .simple)

        #expect(!systemVisible.contains(.monitor))
        #expect(!toolsVisible.contains(.diagnostics))
    }

    @Test func simpleModeKeepsNonGatedSiblingsVisible() {
        // Hiding Monitor/Diagnostics must not take Displays/Health/Optimize/
        // Uninstall/Settings down with them.
        let systemVisible = SidebarSection.system.visibleItems(for: .simple)
        let toolsVisible = SidebarSection.tools.visibleItems(for: .simple)

        #expect(systemVisible.contains(.displays))
        #expect(systemVisible.contains(.health))
        #expect(toolsVisible.contains(.optimize))
        #expect(toolsVisible.contains(.uninstall))
        #expect(toolsVisible.contains(.settings))
    }

    @Test func gatedItemsStayInAllCasesSoHotkeysStillWork() {
        // RootView's ⌘1-9 bindings iterate SidebarItem.allCases directly —
        // gating must be display-only, never remove a case.
        #expect(SidebarItem.allCases.contains(.monitor))
        #expect(SidebarItem.allCases.contains(.diagnostics))
    }
}

@Suite("Sidebar status text")
struct SidebarStatusTextTests {
    @Test func proModeUsesOpsConsolePhrasing() {
        #expect(SidebarView.statusText(mode: .pro, hasCritical: true, hasWarning: false) == "ATTENTION NEEDED")
        #expect(SidebarView.statusText(mode: .pro, hasCritical: false, hasWarning: true) == "MINOR ISSUES")
        #expect(SidebarView.statusText(mode: .pro, hasCritical: false, hasWarning: false) == "ALL SYSTEMS NOMINAL")
    }

    @Test func simpleModeUsesPlainLanguage() {
        #expect(SidebarView.statusText(mode: .simple, hasCritical: true, hasWarning: false) == "Needs attention")
        #expect(SidebarView.statusText(mode: .simple, hasCritical: false, hasWarning: true) == "A couple of small things")
        #expect(SidebarView.statusText(mode: .simple, hasCritical: false, hasWarning: false) == "Everything's fine")
    }

    @Test func criticalTakesPrecedenceOverWarningInBothModes() {
        #expect(SidebarView.statusText(mode: .pro, hasCritical: true, hasWarning: true) == "ATTENTION NEEDED")
        #expect(SidebarView.statusText(mode: .simple, hasCritical: true, hasWarning: true) == "Needs attention")
    }
}
