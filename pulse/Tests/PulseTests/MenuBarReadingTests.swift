import Foundation
import PulseKit
import Testing

@testable import Pulse

private func makeSnapshot(
    cpuTotalPercent: Double = 5,
    memoryUsedBytes: UInt64 = 4_000_000_000,
    cpuTempC: Double? = nil,
    battery: BatteryHealth? = nil
) -> SystemSnapshot {
    SystemSnapshot(
        timestamp: Date(),
        cpuTotalPercent: cpuTotalPercent,
        cpuPerCore: [], cpuEfficiencyPercent: nil, cpuPerformancePercent: nil,
        loadAverage1m: 1,
        memoryUsedBytes: memoryUsedBytes,
        memoryTotalBytes: 16_000_000_000,
        memoryAppBytes: 0, memoryWiredBytes: 0, memoryCompressedBytes: 0,
        swapUsedBytes: 0, memoryPressure: .normal,
        diskFreeBytes: 100_000_000_000, diskTotalBytes: 500_000_000_000,
        diskWeeklyGrowthBytes: nil,
        networkBytesInPerSecond: 0, networkBytesOutPerSecond: 0,
        thermal: .nominal, sensors: SensorReadings(cpuTempC: cpuTempC),
        sleepAssertions: [], topProcesses: [], uptime: 100,
        battery: battery)
}

private func makeBattery(charge: Int, isCharging: Bool = false) -> BatteryHealth {
    BatteryHealth(
        capacityPercent: 95, cycleCount: 100, isCharging: isCharging, isOnAC: isCharging,
        currentChargePercent: charge, timeToEvent: nil, condition: "Normal")
}

@Suite("MenuBar battery reading")
struct MenuBarBatteryReadingTests {
    @Test func chargingKeepsFillLevelAndTintsGreen() {
        let reading = MenuBarStat.battery.reading(
            from: makeSnapshot(battery: makeBattery(charge: 55, isCharging: true)))
        #expect(reading == MenuBarReading(
            value: 55, symbol: "battery.50percent", severity: .charging))
    }

    @Test func fillTracksChargeLevel() {
        let cases: [(Int, String)] = [
            (100, "battery.100percent"), (80, "battery.75percent"),
            (55, "battery.50percent"), (28, "battery.25percent"),
            (13, "battery.25percent"), (12, "battery.0percent"), (5, "battery.0percent"),
        ]
        for (charge, symbol) in cases {
            let reading = MenuBarStat.battery.reading(
                from: makeSnapshot(battery: makeBattery(charge: charge)))
            #expect(reading?.symbol == symbol, "charge \(charge)")
        }
    }

    @Test func lowChargeSeverities() {
        func severity(_ charge: Int) -> MenuBarSeverity? {
            MenuBarStat.battery.reading(
                from: makeSnapshot(battery: makeBattery(charge: charge)))?.severity
        }
        #expect(severity(50) == .nominal)
        #expect(severity(20) == .warning)
        #expect(severity(10) == .critical)
    }

    @Test func noBatteryMeansNoReading() {
        #expect(MenuBarStat.battery.reading(from: makeSnapshot()) == nil)
    }
}

@Suite("MenuBar temp reading")
struct MenuBarTempReadingTests {
    @Test func thermometerBandsAndSeverity() {
        func reading(_ temp: Double) -> MenuBarReading? {
            MenuBarStat.cpuTemp.reading(from: makeSnapshot(cpuTempC: temp))
        }
        #expect(reading(45) == MenuBarReading(
            value: 45, symbol: "thermometer.low", severity: .nominal))
        #expect(reading(70) == MenuBarReading(
            value: 70, symbol: "thermometer.medium", severity: .nominal))
        #expect(reading(85) == MenuBarReading(
            value: 85, symbol: "thermometer.high", severity: .nominal))
        #expect(reading(92) == MenuBarReading(
            value: 92, symbol: "thermometer.high", severity: .warning))
        #expect(reading(101) == MenuBarReading(
            value: 101, symbol: "thermometer.high", severity: .critical))
        #expect(reading(59.6)?.symbol == "thermometer.medium", "rounds to 60 first")
    }

    @Test func noSensorMeansNoReading() {
        #expect(MenuBarStat.cpuTemp.reading(from: makeSnapshot()) == nil)
    }
}

@Suite("MenuBar load readings")
struct MenuBarLoadReadingTests {
    @Test func cpuKeepsSymbolAndTintsByLoad() {
        func reading(_ percent: Double) -> MenuBarReading? {
            MenuBarStat.cpu.reading(from: makeSnapshot(cpuTotalPercent: percent))
        }
        #expect(reading(40) == MenuBarReading(
            value: 40, symbol: "waveform.path.ecg", severity: .nominal))
        #expect(reading(88)?.severity == .warning)
        #expect(reading(97)?.severity == .critical)
    }

    @Test func memoryFillsChipUnderPressure() {
        func reading(_ usedBytes: UInt64) -> MenuBarReading? {
            MenuBarStat.memory.reading(from: makeSnapshot(memoryUsedBytes: usedBytes))
        }
        #expect(reading(8_000_000_000) == MenuBarReading(
            value: 50, symbol: "memorychip", severity: .nominal))
        #expect(reading(14_000_000_000) == MenuBarReading(
            value: 88, symbol: "memorychip.fill", severity: .warning))
        #expect(reading(15_500_000_000)?.severity == .critical)
    }
}
