import Testing
import PulseKit

@Suite("Provider endpoint validation")
struct ProviderURLTests {
    @Test func credentialsStayBoundToTheirEndpoint() {
        #expect(AgentConfiguration.credentialsMatch(selectedEndpoint: "https://example.com/v1/", storedEndpoint: "https://example.com/v1"))
        #expect(!AgentConfiguration.credentialsMatch(selectedEndpoint: "http://127.0.0.1:48123/v1", storedEndpoint: "https://example.com/v1"))
        #expect(!AgentConfiguration.credentialsMatch(selectedEndpoint: "https://other.example/v1", storedEndpoint: "https://example.com/v1"))
    }

    @Test func encryptedRemoteProviderAndLocalDevelopmentAreAccepted() {
        for value in ["https://provider.example/v1", "http://localhost:1234/v1", "http://127.0.0.1:8000", "http://[::1]:8000"] {
            #expect(AgentConfiguration.providerURL(value) != nil)
        }
    }
    @Test func unsafeOrAmbiguousProviderAddressIsRejected() {
        for value in ["http://provider.example/v1", "ftp://localhost", "https://user:password@provider.example", "https://provider.example?api_key=fixture", "https://provider.example#fragment", "https:///v1", "not a URL", "http://localhost.example/v1"] {
            #expect(AgentConfiguration.providerURL(value) == nil)
        }
    }
}
