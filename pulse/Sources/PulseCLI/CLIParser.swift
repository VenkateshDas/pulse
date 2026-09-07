import Foundation

public struct CLIUsageError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

/// Closed command grammar: misspelled flags never silently authorize an action.
public struct CLIParser: Sendable {
    public static let commands: Set<String> = ["vitals", "diagnose", "procs", "attention", "anomalies", "growth", "verdict", "clean", "uninstall", "display", "sleep", "sensors", "undo", "duplicates", "speedtest"]
    public static let usage: [String: String] = [
        "vitals": "vitals [--lite]", "diagnose": "diagnose", "procs": "procs [--by cpu|mem] [--limit N]",
        "attention": "attention", "anomalies": "anomalies [--hours N]", "growth": "growth [--days N] [--limit N]",
        "verdict": "verdict <directory>", "clean": "clean [--scan | --target <exact-path-ID> | --all-safe] [--dry-run] [--yes]",
        "uninstall": "uninstall [--list | <exact-name|bundle-ID|path>] [--dry-run] [--yes]",
        "display": "display [get | set <-1...1>] [--display ID] (requires Pulse.app)",
        "sleep": "sleep [status | prevent [--until seconds] | allow] (requires Pulse.app)",
        "sensors": "sensors", "undo": "undo [list | restore <ID>]", "duplicates": "duplicates <directory> [--min-size-mb N]",
        "speedtest": "speedtest [--cached] (reads history; never runs a subprocess)"
    ]
    private static let aliases = ["ps": "procs", "alerts": "attention", "spikes": "anomalies", "rm": "uninstall", "brightness": "display", "awake": "sleep", "smc": "sensors", "restore": "undo", "dups": "duplicates", "speed": "speedtest"]
    private static let short = ["h": "help", "v": "version", "n": "limit", "d": "days", "t": "target"]
    private static let valueKeys: Set<String> = ["limit", "by", "days", "hours", "target", "display", "until", "min-size-mb"]
    public let subcommand: String?
    public let flags: Set<String>
    public let options: [String: String]
    public let positional: [String]
    private let errors: [String]
    public var isDryRun: Bool { flags.contains("dry-run") || !flags.contains("yes") || flags.contains("scan") }

    public init(arguments: [String] = Array(CommandLine.arguments.dropFirst())) {
        var sub: String?, flags = Set<String>(), options = [String: String](), positional = [String](), errors = [String]()
        var i = 0, literal = false
        while i < arguments.count {
            let arg = arguments[i]
            defer { i += 1 }
            if arg == "--" && !literal { literal = true; continue }
            if !literal && arg.hasPrefix("-") && Double(arg) == nil {
                let parts = String(arg.dropFirst(arg.hasPrefix("--") ? 2 : 1)).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let raw = parts.first.map(String.init) ?? ""
                let key = Self.short[raw] ?? raw
                if flags.contains(key) || options[key] != nil { errors.append("Repeated option --\(key)") }
                if Self.valueKeys.contains(key) {
                    if parts.count == 2 { options[key] = String(parts[1]) }
                    else if i + 1 < arguments.count && (!arguments[i+1].hasPrefix("-") || Double(arguments[i+1]) != nil) {
                        i += 1; options[key] = arguments[i]
                    } else { errors.append("Missing value for --\(key)") }
                } else {
                    if parts.count == 2 { errors.append("Flag --\(key) does not take a value") }
                    flags.insert(key)
                }
            } else if sub == nil { sub = Self.aliases[arg] ?? arg }
            else { positional.append(arg) }
        }
        self.subcommand = sub; self.flags = flags; self.options = options; self.positional = positional; self.errors = errors
    }

    public func validate() throws {
        func fail(_ message: String) throws { throw CLIUsageError(message) }
        if let error = errors.first { try fail(error) }
        let command = subcommand ?? "help"
        guard Self.commands.contains(command) || ["help", "version"].contains(command) else { try fail("Unknown command '\(command)'"); return }
        let allowed: [String: Set<String>] = [
            "vitals": ["lite"], "procs": ["by", "limit"], "anomalies": ["hours"],
            "growth": ["days", "limit"], "clean": ["scan", "target", "all-safe", "dry-run", "yes"],
            "uninstall": ["list", "dry-run", "yes"], "display": ["display"], "sleep": ["until"],
            "duplicates": ["min-size-mb"], "speedtest": ["cached"]]
        let permitted = (allowed[command] ?? []).union(["json", "help", "version"])
        for key in flags.union(options.keys) where !permitted.contains(key) { try fail("Unknown option --\(key) for \(command)") }
        for key in ["limit", "days", "hours"] {
            if let raw = options[key], Int(raw).map({ $0 > 0 && $0 <= 100_000 }) != true { try fail("--\(key) must be an integer from 1 to 100000") }
        }
        for key in ["until", "min-size-mb"] {
            if let raw = options[key], Double(raw).map({ $0.isFinite && $0 > 0 && $0 <= 31_536_000 }) != true { try fail("--\(key) must be finite, positive, and at most 31536000") }
        }
        if let raw = options["display"], UInt32(raw) == nil { try fail("--display must be a display ID") }
        if let by = options["by"], !["cpu", "mem"].contains(by) { try fail("--by must be cpu or mem") }
        if let target = options["target"], target.isEmpty { try fail("--target cannot be empty") }
        if hasFlag("help", "version") { return }
        switch command {
        case "verdict", "duplicates": if positional.count != 1 { try fail("\(command) requires one directory path") }
        case "uninstall":
            if positional.count > 1 || (hasFlag("yes") && (positional.isEmpty || hasFlag("list"))) { try fail("uninstall requires one exact app name, bundle ID, or path") }
        case "display":
            let action = positional.first ?? "get"
            if action == "set" {
                guard positional.count == 2, let value = Double(positional[1]), value.isFinite, (-1...1).contains(value) else { try fail("display set requires a finite value from -1 to 1"); return }
            } else if action != "get" || positional.count > 1 { try fail("Usage: display [get | set <value>] [--display ID]") }
        case "sleep":
            if positional.count > 1 || !["status", "prevent", "allow"].contains(positional.first ?? "status") { try fail("Usage: sleep [status | prevent | allow]") }
            if options["until"] != nil && positional.first != "prevent" { try fail("--until requires sleep prevent") }
        case "undo":
            if !(positional.isEmpty || positional == ["list"] || (positional.count == 2 && positional[0] == "restore" && positional[1].count >= 8)) { try fail("Usage: undo [list | restore <ID, at least 8 characters>]") }
        default: if !positional.isEmpty { try fail("Unexpected argument for \(command)") }
        }
        if command == "clean" {
            if options["target"] != nil && hasFlag("all-safe") { try fail("Choose --target or --all-safe") }
            if hasFlag("yes") && !hasFlag("scan") && options["target"] == nil && !hasFlag("all-safe") { try fail("clean --yes requires --target ID or --all-safe") }
        }
    }
    public func hasFlag(_ names: String...) -> Bool { names.contains { flags.contains(Self.short[$0] ?? $0) } }
    public func stringOption(_ names: String...) -> String? { names.compactMap { options[Self.short[$0] ?? $0] }.first }
    public func intOption(_ names: String..., default fallback: Int? = nil) -> Int? { names.compactMap { options[Self.short[$0] ?? $0].flatMap(Int.init) }.first ?? fallback }
    public func doubleOption(_ names: String..., default fallback: Double? = nil) -> Double? { names.compactMap { options[Self.short[$0] ?? $0].flatMap(Double.init) }.first ?? fallback }
}
