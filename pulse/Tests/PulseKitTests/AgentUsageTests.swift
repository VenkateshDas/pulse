import Foundation
import Testing
import PulseKit

@Suite("Usage wire contract")
struct AgentUsageTests {
    private func snapshot(cost: String, historical: Bool = false) throws -> AgentUsageSnapshot {
        let json = """
        {"context":null,"totals":{"input":1000,"output":100,"cacheRead":700,"cacheWrite":0,"totalTokens":1100,"requests":1,"missingUsage":0,"missingCost":0,"costUSD":\(cost),"compactionTokens":0},"historical":\(historical)}
        """
        return try JSONDecoder().decode(AgentUsageSnapshot.self, from: Data(json.utf8))
    }

    @Test func reportedFreeCostIsDistinctFromUnavailableCost() throws {
        let free = try snapshot(cost: #""0""#)
        let unavailable = try snapshot(cost: "null", historical: true)
        #expect(free.totals.costUSD == "0")
        #expect(unavailable.totals.costUSD == nil)
        #expect(unavailable.historical)
        #expect(unavailable.context == nil)
    }

    @Test func cachedInputIsSeparateWithoutInflatingTotalConsumption() throws {
        let value = try snapshot(cost: #""0.000123456789""#)
        #expect(value.totals.input == 1000)
        #expect(value.totals.cacheRead == 700)
        #expect(value.totals.totalTokens == value.totals.input + value.totals.output)
        let roundTrip = try JSONDecoder().decode(AgentUsageSnapshot.self, from: JSONEncoder().encode(value))
        #expect(roundTrip == value)
        #expect(roundTrip.totals.costUSD == "0.000123456789")
    }
}
