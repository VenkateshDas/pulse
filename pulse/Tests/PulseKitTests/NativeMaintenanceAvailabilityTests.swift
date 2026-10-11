import Testing
@testable import PulseKit

@Suite("Native maintenance availability")
struct NativeMaintenanceAvailabilityTests {
    @Test func unsupportedOperationsCannotRunOrRequestElevation() async throws {
        for task in OptimizeEngine.tasks where task.id != "saved_state_cleanup" {
            #expect(await task.skipCheck() != nil)
            let result = try await task.run()
            #expect(!result.success)
            #expect(result.bytesFreed == 0)
            #expect(result.bytesMovedToTrash == 0)
        }
        for operation in PrivilegedOperation.allCases {
            let result = await PrivilegedRunner.run(operation)
            #expect(!result.success)
            #expect(result.summary.contains("not run"))
        }
    }
}
