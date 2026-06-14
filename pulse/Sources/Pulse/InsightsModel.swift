import AppKit
import Foundation
import Observation
import PulseKit

/// Drives the Disk → Insights tab: runs the curated hidden-space scan and
/// reveals items in Finder. Read-only — Insights surface space, they never
/// delete (that's Reclaim's job).
@MainActor
@Observable
final class InsightsModel {
    private(set) var insights: [Insight] = []
    private(set) var isScanning = false
    private(set) var hasScanned = false

    private let scanner = InsightScanner()

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task { [scanner] in
            let found = await scanner.scan()
            self.insights = found
            self.isScanning = false
            self.hasScanned = true
        }
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    var totalBytes: Int64 { insights.reduce(0) { $0 + $1.bytes } }
    func bytes(of kind: Insight.Kind) -> Int64 {
        insights.filter { $0.kind == kind }.reduce(0) { $0 + $1.bytes }
    }
}
