import Foundation
import Testing

@testable import PulseKit

@Suite("MenuBarState")
struct MenuBarStateTests {
    @Test("starts collapsed")
    func initialState() {
        let state = MenuBarState()
        #expect(state.isCollapsed)
        #expect(!state.isExpanded)
        #expect(state.phase == .collapsed)
    }

    @Test("toggle flips between collapsed and expanded")
    func toggle() {
        var state = MenuBarState()
        state.toggle()
        #expect(state.isExpanded)
        state.toggle()
        #expect(state.isCollapsed)
    }

    @Test("collapse and expand set phase directly")
    func directSetters() {
        var state = MenuBarState()
        state.expand()
        #expect(state.isExpanded)
        state.collapse()
        #expect(state.isCollapsed)
    }

    @Test("separator length is large when collapsed")
    func separatorLengthCollapsed() {
        let state = MenuBarState(screenWidth: 1920)
        #expect(state.separatorLength == 3840)
    }

    @Test("separator length is 24 when expanded with separator visible")
    func separatorLengthExpanded() {
        var state = MenuBarState(showSeparator: true)
        state.expand()
        #expect(state.separatorLength == 24)
    }

    @Test("separator length is 0 when expanded with separator hidden")
    func separatorLengthHidden() {
        var state = MenuBarState(showSeparator: false)
        state.expand()
        #expect(state.separatorLength == 0)
    }

    @Test("collapse width capped at 10_000")
    func collapseWidthCapped() {
        let state = MenuBarState(screenWidth: 6000)
        #expect(state.collapseWidth == 10_000)
    }

    @Test("updateScreenWidth recalculates collapse width")
    func screenWidthUpdate() {
        var state = MenuBarState(screenWidth: 1920)
        #expect(state.collapseWidth == 3840)
        state.updateScreenWidth(2560)
        #expect(state.collapseWidth == 5120)
    }

    @Test("chevron symbol reflects state")
    func chevronSymbol() {
        var state = MenuBarState()
        #expect(state.chevronSymbol == "chevron.right.2")
        state.expand()
        #expect(state.chevronSymbol == "chevron.left.2")
    }

    @Test("shouldAutoHide only when expanded and delay > 0")
    func autoHide() {
        var state = MenuBarState(autoHideDelay: 10)
        #expect(!state.shouldAutoHide) // collapsed
        state.expand()
        #expect(state.shouldAutoHide)
        state.autoHideDelay = 0
        #expect(!state.shouldAutoHide) // delay disabled
    }

    @Test("disabled state doesn't affect phase logic")
    func disabledState() {
        var state = MenuBarState(isEnabled: false)
        state.toggle()
        #expect(state.isExpanded) // state still transitions
    }
}
