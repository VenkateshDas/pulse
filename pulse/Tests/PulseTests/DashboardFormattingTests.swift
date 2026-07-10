import Testing

@testable import Pulse

@Suite("DashboardFormatting CPU")
struct DashboardFormattingCPUTests {
    @Test func proShowsEfficiencyPerformanceSplitAndGPU() {
        let line1 = DashboardFormatting.cpuLine1(
            mode: .pro, efficiencyPercent: 40, performancePercent: 12, coreCount: 8, gpuPercent: 10)
        #expect(line1 == "E 40% · P 12% · GPU 10%")
    }

    @Test func proFallsBackToCoreCountWhenNoSplitAvailable() {
        let line1 = DashboardFormatting.cpuLine1(
            mode: .pro, efficiencyPercent: nil, performancePercent: nil, coreCount: 8, gpuPercent: nil)
        #expect(line1 == "8 cores")
    }

    @Test func simpleDropsSplitAndGPUEntirely() {
        let line1 = DashboardFormatting.cpuLine1(
            mode: .simple, efficiencyPercent: 40, performancePercent: 12, coreCount: 8, gpuPercent: 10)
        #expect(line1 == "8 cores")
        #expect(!line1.contains("E "))
        #expect(!line1.contains("GPU"))
    }

    @Test func simpleSingularizesOneCore() {
        #expect(DashboardFormatting.cpuLine1(mode: .simple, efficiencyPercent: nil, performancePercent: nil, coreCount: 1, gpuPercent: nil) == "1 core")
    }

    @Test func loadAverageOnlyShownInPro() {
        #expect(DashboardFormatting.cpuLine2(mode: .pro, loadAverage1m: 5.2) == "load  5.20")
        #expect(DashboardFormatting.cpuLine2(mode: .simple, loadAverage1m: 5.2) == nil)
    }
}

@Suite("DashboardFormatting Memory")
struct DashboardFormattingMemoryTests {
    @Test func proUsesAbbreviatedLabels() {
        let line1 = DashboardFormatting.memoryLine1(mode: .pro, usedBytes: 8_000_000_000, freeBytes: 3_000_000_000)
        #expect(line1.hasPrefix("U:"))
        #expect(line1.contains("F:"))
    }

    @Test func simpleUsesPlainSentence() {
        let line1 = DashboardFormatting.memoryLine1(mode: .simple, usedBytes: 8_000_000_000, freeBytes: 3_000_000_000)
        #expect(line1.contains("used"))
        #expect(line1.contains("free"))
        #expect(!line1.contains("U:"))
    }

    @Test func swapOnlyShownInPro() {
        #expect(DashboardFormatting.memoryLine2(mode: .pro, swapUsedBytes: 400_000_000, pressureSuffix: "") != nil)
        #expect(DashboardFormatting.memoryLine2(mode: .simple, swapUsedBytes: 400_000_000, pressureSuffix: "") == nil)
    }

    @Test func breakdownVisualOnlyInPro() {
        #expect(DashboardFormatting.showsMemoryBreakdown(mode: .pro) == true)
        #expect(DashboardFormatting.showsMemoryBreakdown(mode: .simple) == false)
    }
}

@Suite("DashboardFormatting Thermal")
struct DashboardFormattingThermalTests {
    @Test func proShowsPerSensorBreakdown() {
        let line1 = DashboardFormatting.thermalLine1(mode: .pro, cpuTempC: 68, gpuTempC: 55)
        #expect(line1 == "CPU 68° · GPU 55°")
    }

    @Test func simpleGivesPlainVerdictByHottestSensor() {
        #expect(DashboardFormatting.thermalLine1(mode: .simple, cpuTempC: 50, gpuTempC: 40) == "Running cool")
        #expect(DashboardFormatting.thermalLine1(mode: .simple, cpuTempC: 80, gpuTempC: 40) == "Getting warm")
        #expect(DashboardFormatting.thermalLine1(mode: .simple, cpuTempC: 95, gpuTempC: 40) == "Running hot")
    }

    @Test func simpleWithNoSensorsReturnsEmptyString() {
        #expect(DashboardFormatting.thermalLine1(mode: .simple, cpuTempC: nil, gpuTempC: nil) == "")
    }

    @Test func batteryFanWattageOnlyShownInPro() {
        #expect(DashboardFormatting.thermalLine2(mode: .pro, parts: ["fan 2000 rpm"]) == "fan 2000 rpm")
        #expect(DashboardFormatting.thermalLine2(mode: .simple, parts: ["fan 2000 rpm"]) == nil)
    }

    @Test func headroomAndTrendChipsOnlyInPro() {
        #expect(DashboardFormatting.showsThermalStats(mode: .pro) == true)
        #expect(DashboardFormatting.showsThermalStats(mode: .simple) == false)
    }

    @Test func fallbackCopyIsPlainInSimpleMode() {
        #expect(DashboardFormatting.thermalFallbackLine2(mode: .pro) == "no SMC sensors found")
        #expect(DashboardFormatting.thermalFallbackLine2(mode: .simple) == "no sensors on this Mac")
    }
}
