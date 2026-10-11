import Foundation
import Testing
@testable import PulseKit

@Suite("Bounded network estimates")
struct SpeedTestEstimateTests {
    @Test func transferRatesUseMegabitsAndRejectInvalidDurations() throws {
        #expect(try SpeedTestRunner.rateMbps(bytes: 4_000_000, seconds: 2) == 16)
        for duration in [0, -1, Double.infinity, Double.nan] {
            #expect(throws: SpeedTestError.self) {
                try SpeedTestRunner.rateMbps(bytes: 4_000_000, seconds: duration)
            }
        }
    }

    @Test func historicalMeasurementsWithoutMethodStillDecode() throws {
        let data = Data(#"{"downloadMbps":100,"uploadMbps":20,"responsivenessRPM":1200,"baseRTTMillis":12,"date":0}"#.utf8)
        let result = try JSONDecoder().decode(SpeedTestResult.self, from: data)
        #expect(result.method == nil)
        #expect(result.responsivenessRPM == 1200)
    }
}
