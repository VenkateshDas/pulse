import Foundation

/// A saved speed-test result. Older results may contain Apple RPM measurements.
public struct SpeedTestResult: Sendable, Equatable, Codable, Identifiable {
    public var id: Date { date }
    public let downloadMbps: Double
    public let uploadMbps: Double
    /// Round-trips per minute under working load — Apple's "Responsiveness" metric.
    public let responsivenessRPM: Int?
    public let baseRTTMillis: Double?
    public let date: Date
    public let method: String?

    public init(
        downloadMbps: Double, uploadMbps: Double, responsivenessRPM: Int?,
        baseRTTMillis: Double?, date: Date = Date(), method: String? = nil
    ) {
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.responsivenessRPM = responsivenessRPM
        self.baseRTTMillis = baseRTTMillis
        self.date = date
        self.method = method
    }
}

public enum SpeedTestError: Error, Sendable {
    case alreadyRunning
    case toolUnavailable
    case cancelled
    case malformedOutput
    case processFailed(Int32)
}

/// Bounded, in-process HTTPS transfers to Cloudflare's public speed endpoints.
/// Reports transfer-rate estimates; it does not measure Apple's loaded RPM metric.
/// Endpoint reference: https://github.com/cloudflare/speedtest/blob/main/README.md
public actor SpeedTestRunner {
    private var activeSession: URLSession?
    public static let downloadBytes = 4_000_000
    public static let uploadBytes = 2_000_000
    public static let samples = 3

    public init() {}

    public func run() async throws -> SpeedTestResult {
        guard activeSession == nil else { throw SpeedTestError.alreadyRunning }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration)
        activeSession = session
        defer { session.invalidateAndCancel(); activeSession = nil }

        return try await withTaskCancellationHandler {
            var latency: [Double] = []
            for _ in 0..<Self.samples {
                try Task.checkCancellation()
                let start = ContinuousClock.now
                let (_, response) = try await session.data(for: Self.request(path: "__down?bytes=0"))
                try Self.validate(response)
                latency.append(Self.seconds(since: start) * 1000)
            }
            var downloads: [Double] = []
            var uploads: [Double] = []
            for _ in 0..<Self.samples {
                try Task.checkCancellation()
                let start = ContinuousClock.now
                let (data, response) = try await session.data(for: Self.request(path: "__down?bytes=\(Self.downloadBytes)"))
                try Self.validate(response)
                guard data.count == Self.downloadBytes else { throw SpeedTestError.malformedOutput }
                downloads.append(try Self.rateMbps(bytes: data.count, seconds: Self.seconds(since: start)))
            }
            let payload = Data(repeating: 0x61, count: Self.uploadBytes)
            for _ in 0..<Self.samples {
                try Task.checkCancellation()
                var request = Self.request(path: "__up")
                request.httpMethod = "POST"
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                let start = ContinuousClock.now
                let (_, response) = try await session.upload(for: request, from: payload)
                try Self.validate(response)
                uploads.append(try Self.rateMbps(bytes: payload.count, seconds: Self.seconds(since: start)))
            }
            try Task.checkCancellation()
            return SpeedTestResult(downloadMbps: Self.median(downloads), uploadMbps: Self.median(uploads),
                                   responsivenessRPM: nil, baseRTTMillis: Self.median(latency), method: "bounded-https")
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    public func cancel() { activeSession?.invalidateAndCancel() }

    private static func request(path: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://speed.cloudflare.com/" + path)!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SpeedTestError.malformedOutput
        }
    }

    static func rateMbps(bytes: Int, seconds: Double) throws -> Double {
        guard bytes > 0, seconds > 0, seconds.isFinite else { throw SpeedTestError.malformedOutput }
        let rate = Double(bytes) * 8 / seconds / 1_000_000
        guard rate.isFinite else { throw SpeedTestError.malformedOutput }
        return rate
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }

    private static func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
}
