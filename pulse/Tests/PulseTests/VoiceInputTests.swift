import Dispatch
import Testing
@preconcurrency import Speech
@testable import Pulse

@Suite("Dictation permission callbacks")
struct VoiceInputTests {
    @Test @MainActor func backgroundAuthorizationReturnsWithoutActorTrap() async {
        let granted = await VoiceInput.speechPermission { callback in
            DispatchQueue.global().async { callback(.authorized) }
        }
        #expect(granted)
    }

    @Test @MainActor func deniedAuthorizationReturnsFalse() async {
        let granted = await VoiceInput.speechPermission { callback in
            DispatchQueue.global().async { callback(.denied) }
        }
        #expect(!granted)
    }
}
