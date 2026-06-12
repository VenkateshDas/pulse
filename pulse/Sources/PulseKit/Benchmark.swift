import CryptoKit
import Foundation

/// One micro-benchmark run. Three independent throughput numbers; the
/// score is a transparent average of each phase against fixed reference
/// constants (documented on `referenceScore`) — no opaque magic number.
public struct BenchmarkResult: Sendable, Codable, Equatable {
    public let date: Date
    /// SHA256 hashing throughput, MB/s (single core).
    public let cpuHashMBps: Double
    /// Sequential write + F_FULLFSYNC throughput, MB/s.
    public let diskWriteMBps: Double
    /// Large-buffer memcpy throughput, GB/s.
    public let memCopyGBps: Double

    public init(date: Date, cpuHashMBps: Double, diskWriteMBps: Double, memCopyGBps: Double) {
        self.date = date
        self.cpuHashMBps = cpuHashMBps
        self.diskWriteMBps = diskWriteMBps
        self.memCopyGBps = memCopyGBps
    }

    /// Reference machine ≈ base M1: 2000 MB/s SHA256, 3000 MB/s disk
    /// write, 60 GB/s memcpy. Score = mean of the three ratios × 1000,
    /// so 1000 ≈ base M1 and the number scales linearly.
    public static let references = (cpuMBps: 2000.0, diskMBps: 3000.0, memGBps: 60.0)

    public var score: Int {
        let mean =
            (cpuHashMBps / Self.references.cpuMBps
                + diskWriteMBps / Self.references.diskMBps
                + memCopyGBps / Self.references.memGBps) / 3
        return Int((mean * 1000).rounded())
    }
}

/// On-demand micro-benchmarks for the Health page. Runs off the main
/// thread (actor executor); each phase is time- or size-bounded so the
/// whole run stays under ~8 seconds.
public actor Benchmark {
    public struct Config: Sendable {
        /// CPU phase: hash this buffer repeatedly until the duration elapses.
        public var cpuBufferBytes: Int
        public var cpuDuration: TimeInterval
        /// Disk phase: total bytes written in 1 MB chunks, then F_FULLFSYNC.
        public var diskWriteBytes: Int
        /// Memory phase: buffer size copied `memCopyPasses` times.
        public var memBufferBytes: Int
        public var memCopyPasses: Int

        public static let standard = Config(
            cpuBufferBytes: 8 << 20, cpuDuration: 5.0,
            diskWriteBytes: 50 << 20,
            memBufferBytes: 256 << 20, memCopyPasses: 8)

        /// Milliseconds-scale config for unit tests.
        public static let tiny = Config(
            cpuBufferBytes: 1 << 16, cpuDuration: 0.05,
            diskWriteBytes: 1 << 20,
            memBufferBytes: 1 << 20, memCopyPasses: 2)

        public init(
            cpuBufferBytes: Int, cpuDuration: TimeInterval, diskWriteBytes: Int,
            memBufferBytes: Int, memCopyPasses: Int
        ) {
            self.cpuBufferBytes = cpuBufferBytes
            self.cpuDuration = cpuDuration
            self.diskWriteBytes = diskWriteBytes
            self.memBufferBytes = memBufferBytes
            self.memCopyPasses = memCopyPasses
        }
    }

    public init() {}

    public func run(config: Config = .standard) -> BenchmarkResult {
        BenchmarkResult(
            date: .now,
            cpuHashMBps: cpuPhase(config),
            diskWriteMBps: diskPhase(config),
            memCopyGBps: memPhase(config))
    }

    private func cpuPhase(_ config: Config) -> Double {
        let buffer = Data(count: config.cpuBufferBytes)
        var hashed = 0
        var digest = SHA256.hash(data: buffer)  // warm-up + keep result live
        let start = ContinuousClock.now
        while ContinuousClock.now - start < .seconds(config.cpuDuration) {
            digest = SHA256.hash(data: buffer)
            hashed += buffer.count
        }
        let elapsed = (ContinuousClock.now - start).seconds
        withExtendedLifetime(digest) {}
        guard elapsed > 0, hashed > 0 else { return 0 }
        return Double(hashed) / elapsed / 1_048_576
    }

    private func diskPhase(_ config: Config) -> Double {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-bench-\(ProcessInfo.processInfo.processIdentifier).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else { return 0 }
        defer { try? handle.close() }

        let chunk = Data(repeating: 0xA5, count: min(1 << 20, config.diskWriteBytes))
        let start = ContinuousClock.now
        var written = 0
        while written < config.diskWriteBytes {
            guard (try? handle.write(contentsOf: chunk)) != nil else { return 0 }
            written += chunk.count
        }
        // F_FULLFSYNC forces the write through the drive cache — without it
        // a 50 MB write "finishes" in RAM and the number is fiction.
        _ = fcntl(handle.fileDescriptor, F_FULLFSYNC)
        let elapsed = (ContinuousClock.now - start).seconds
        guard elapsed > 0 else { return 0 }
        return Double(written) / elapsed / 1_048_576
    }

    private func memPhase(_ config: Config) -> Double {
        let count = config.memBufferBytes
        let source = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
        let destination = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
        defer {
            source.deallocate()
            destination.deallocate()
        }
        // Touch every page first so the copy measures memory bandwidth,
        // not first-fault zero-fill.
        memset(source, 0x5A, count)
        memset(destination, 0, count)

        let start = ContinuousClock.now
        for _ in 0..<config.memCopyPasses {
            memcpy(destination, source, count)
        }
        let elapsed = (ContinuousClock.now - start).seconds
        guard elapsed > 0 else { return 0 }
        return Double(count) * Double(config.memCopyPasses) / elapsed / 1_073_741_824
    }
}

extension Duration {
    fileprivate var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// Persists benchmark runs (newest last) so "vs last run" survives
/// relaunches. JSON in Application Support, capped at `maxEntries`.
public final class BenchmarkStore {
    public static let maxEntries = 50

    public private(set) var results: [BenchmarkResult]
    private let fileURL: URL?

    public init(fileURL: URL? = BenchmarkStore.defaultFileURL()) {
        self.fileURL = fileURL
        if let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode([BenchmarkResult].self, from: data)
        {
            results = stored
        } else {
            results = []
        }
    }

    public func record(_ result: BenchmarkResult) {
        results.append(result)
        if results.count > Self.maxEntries {
            results.removeFirst(results.count - Self.maxEntries)
        }
        persist()
    }

    public var latest: BenchmarkResult? { results.last }
    /// The run before the latest — the "vs last run" comparison point.
    public var previous: BenchmarkResult? {
        results.count >= 2 ? results[results.count - 2] : nil
    }

    private func persist() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(results) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pulse/benchmark-history.json")
    }
}
