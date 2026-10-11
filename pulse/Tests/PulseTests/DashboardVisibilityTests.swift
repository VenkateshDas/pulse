import Testing
@testable import Pulse

@Suite("Presentation visibility")
struct DashboardVisibilityTests {
    @Test func duplicateWindowEventsCannotKeepPublishingAfterClose() {
        var state = DashboardVisibility()
        state.set(.window, visible: true)
        state.set(.window, visible: true)
        state.set(.window, visible: false)
        #expect(!state.isVisible)
    }
    @Test func closingOneSurfaceKeepsTheOtherVisible() {
        var state = DashboardVisibility()
        state.set(.window, visible: true)
        state.set(.popover, visible: true)
        state.set(.window, visible: false)
        #expect(state.isVisible)
        state.set(.popover, visible: false)
        #expect(!state.isVisible)
    }
    @Test func duplicatePopoverEventsAndRepeatedCloseAreIdempotent() {
        var state = DashboardVisibility()
        state.set(.popover, visible: true)
        state.set(.popover, visible: true)
        state.set(.popover, visible: false)
        state.set(.popover, visible: false)
        #expect(!state.isVisible)
    }
}
