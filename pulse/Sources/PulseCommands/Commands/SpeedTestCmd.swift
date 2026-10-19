import Foundation
import PulseKit

public struct SpeedTestDTO: Codable, Sendable {
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let responsivenessRPM: Int?
    public let baseRTTMillis: Double?
    public let date: Date

    public init(result: SpeedTestResult) {
        self.downloadMbps = (result.downloadMbps * 10).rounded() / 10
        self.uploadMbps = (result.uploadMbps * 10).rounded() / 10
        self.responsivenessRPM = result.responsivenessRPM
        self.baseRTTMillis = result.baseRTTMillis.map { ($0 * 10).rounded() / 10 }
        self.date = result.date
    }
}

public enum SpeedTestCmd {
    public static func run(parser: CLIParser, output: CLIOutput) async {
        // If --cached or no new run requested, check SpeedTestStore
        do {
            let store = SpeedTestStore()
            if let latest = store.results.first {
                let dto = SpeedTestDTO(result: latest)
                if output.isJSON {
                    output.emitJSON(dto)
                } else {
                    output.printHeader("Latest Cached Speed Test")
                    output.printRow(label: "Download", value: "\(dto.downloadMbps) Mbps")
                    output.printRow(label: "Upload", value: "\(dto.uploadMbps) Mbps")
                    if let rtt = dto.baseRTTMillis {
                        output.printRow(label: "Latency (RTT)", value: "\(rtt) ms")
                    }
                    if let rpm = dto.responsivenessRPM {
                        output.printRow(label: "Responsiveness", value: "\(rpm) RPM")
                    }
                }
            } else {
                if output.isJSON {
                    output.emitJSON(["message": "No cached speed test found; run a test from Pulse.app"])
                } else {
                    output.printWarning("No cached speed test found. Run a speed test from the Pulse app to populate history.")
                }
            }
            return
        }

    }
}
