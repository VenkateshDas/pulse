import Foundation

/// The metrics that contribute to the system health score. Weights and
/// thresholds are ported verbatim from mole's `metrics_health.go` (facts,
/// not code). Disk IO has no sampler yet — it is declared so the curve is
/// ready when F7 lands, but reports `nil` and is excluded from scoring.
public enum HealthFactor: String, Sendable, CaseIterable, Hashable {
    case cpu, memory, disk, thermal, diskIO

    /// mole weights: CPU 30, Mem 25, Disk 20, Thermal 15, IO 10 (sum 100).
    public var weight: Double {
        switch self {
        case .cpu: return 30
        case .memory: return 25
        case .disk: return 20
        case .thermal: return 15
        case .diskIO: return 10
        }
    }

    /// Value at or below this loses no points.
    var normal: Double {
        switch self {
        case .cpu: return 50
        case .memory: return 70
        case .disk: return 80
        case .thermal: return 65
        case .diskIO: return 50
        }
    }

    /// Value at or above this loses (near) the full weight.
    var high: Double {
        switch self {
        case .cpu: return 85
        case .memory: return 88
        case .disk: return 93
        case .thermal: return 85
        case .diskIO: return 150
        }
    }

    public var label: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .thermal: return "Thermal"
        case .diskIO: return "Disk IO"
        }
    }
}

public struct HealthScore: Sendable, Equatable {
    public enum Band: String, Sendable {
        case excellent, good, fair, poor

        public init(value: Int) {
            switch value {
            case 85...: self = .excellent
            case 65..<85: self = .good
            case 45..<65: self = .fair
            default: self = .poor
            }
        }
    }

    /// 0…100, higher is healthier.
    public let value: Int
    public let band: Band
    /// Points lost per factor. Absent factors (no data) are omitted.
    public let breakdown: [HealthFactor: Double]

    public init(value: Int, band: Band, breakdown: [HealthFactor: Double]) {
        self.value = value
        self.band = band
        self.breakdown = breakdown
    }

    /// Piecewise penalty curve (mole `metrics_health.go:62-110`):
    /// below normal → 0; normal→high ramps half-weight linearly; above high
    /// → second half ramps over another (high−normal) span, capped at weight.
    static func pointsLost(_ factor: HealthFactor, value: Double) -> Double {
        let n = factor.normal, h = factor.high, w = factor.weight
        guard h > n else { return value > h ? w : 0 }
        if value <= n { return 0 }
        if value <= h {
            return w * 0.5 * (value - n) / (h - n)
        }
        let over = min(1, (value - h) / (h - n))
        return w * (0.5 + 0.5 * over)
    }

    public static func evaluate(_ s: SystemSnapshot) -> HealthScore {
        var lost: [HealthFactor: Double] = [:]
        var availableWeight = 0.0

        func add(_ f: HealthFactor, _ v: Double) {
            lost[f] = pointsLost(f, value: v)
            availableWeight += f.weight
        }

        add(.cpu, s.cpuTotalPercent)
        add(.memory, s.memoryUsedFraction * 100)
        add(.disk, s.diskUsedFraction * 100)

        // Thermal: prefer SMC CPU temp; fall back to the ThermalLevel enum
        // mapped onto the °C scale so the factor still counts.
        if let t = s.sensors.cpuTempC {
            add(.thermal, t)
        } else {
            let synthetic: Double
            switch s.thermal {
            case .nominal: synthetic = 50
            case .fair: synthetic = 70
            case .serious: synthetic = 85
            case .critical: synthetic = 100
            }
            add(.thermal, synthetic)
        }
        // diskIO intentionally omitted until a sampler exists (F7).

        // Memory pressure penalty stacks on top of the % curve.
        switch s.memoryPressure {
        case .warning: lost[.memory, default: 0] += 5
        case .critical: lost[.memory, default: 0] += 15
        case .normal: break
        }

        let totalLost = lost.values.reduce(0, +)
        // Scale lost points to a 0…100 axis over the factors we actually have.
        let scaled = availableWeight > 0 ? totalLost * (100 / availableWeight) : 0
        let value = max(0, min(100, Int((100 - scaled).rounded())))
        return HealthScore(value: value, band: Band(value: value), breakdown: lost)
    }
}
