import Foundation
import Testing

@testable import Pulse

private func makeSuite() -> UserDefaults {
    let suite = UserDefaults(suiteName: "pulse-displaymode-tests-\(UUID().uuidString)")!
    return suite
}

@Suite("DisplayModeManager")
@MainActor
struct DisplayModeManagerTests {
    @Test func freshInstallDefaultsToSimple() {
        let defaults = makeSuite()
        // No onboarding-complete flag and no saved mode: brand-new install.
        let manager = DisplayModeManager(defaults: defaults)
        #expect(manager.current == .simple)
    }

    @Test func existingInstallDefaultsToPro() {
        let defaults = makeSuite()
        defaults.set(true, forKey: OnboardingView.completeKey)
        let manager = DisplayModeManager(defaults: defaults)
        #expect(manager.current == .pro)
    }

    @Test func explicitChoiceWinsOverExistingInstallDefault() {
        let defaults = makeSuite()
        defaults.set(true, forKey: OnboardingView.completeKey)
        DisplayModeManager(defaults: defaults).set(.simple)

        // Re-create the manager as a fresh process launch would: the saved
        // choice must win over the "existing install -> pro" default.
        let reloaded = DisplayModeManager(defaults: defaults)
        #expect(reloaded.current == .simple)
    }

    @Test func setPersistsAndReloads() {
        let defaults = makeSuite()
        let manager = DisplayModeManager(defaults: defaults)
        manager.set(.pro)
        #expect(manager.current == .pro)

        let reloaded = DisplayModeManager(defaults: defaults)
        #expect(reloaded.current == .pro)
    }
}
