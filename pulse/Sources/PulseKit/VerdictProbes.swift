import CoreServices
import Foundation

/// Bounded "how dead is this tree" walk. mtime only — APFS atime is
/// unreliable (noatime mounts, relatime semantics), so it is never read.
///
/// Two dates come back, and the difference is the whole point: dead apps'
/// folders get touched forever by housekeeping (Finder writing .DS_Store,
/// leftover shell hooks appending logs, agents rewriting state files), which
/// makes a naive newest-mtime scream "changed today" about a tool deleted
/// months ago. `newestContent` ignores that noise; `newestAny` keeps the
/// honest raw answer for display.
public enum StalenessProbe {
    public struct Result: Sendable, Equatable {
        /// Newest mtime among substantive files (housekeeping excluded).
        public let newestContent: Date?
        /// Name of that newest substantive file — shown so the user can judge.
        public let newestContentName: String?
        /// Newest mtime among everything, housekeeping included.
        public let newestAny: Date?
        public let fileCount: Int
        public let sizeBytes: UInt64
        /// True when the walk stopped at the entry cap — dates are then a
        /// lower bound, not the whole truth.
        public let truncated: Bool
    }

    /// File names / extensions / directory names whose churn says nothing
    /// about whether the folder's *owner* is alive: Finder metadata, logs,
    /// lockfiles, caches, telemetry, shell state.
    static let noiseNames: Set<String> = [".DS_Store", ".localized", "lock", ".lock"]
    static let noiseExtensions: Set<String> = ["log", "lock", "pid", "tmp"]
    static let noiseDirNames: Set<String> = [
        "logs", "log", "cache", "caches", "tmp", "temp", "telemetry", "crashes",
    ]

    static func isNoise(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if noiseNames.contains(name) { return true }
        if noiseExtensions.contains(url.pathExtension.lowercased()) { return true }
        // Anything living under a logs/cache/tmp directory inside the target.
        for component in url.pathComponents.suffix(4).dropLast()
        where noiseDirNames.contains(component.lowercased()) {
            return true
        }
        // State/history files apps rewrite on every run of anything nearby.
        let lower = name.lowercased()
        if lower.hasSuffix("history") || lower.hasSuffix(".json.bak") { return true }
        return false
    }

    /// Walks up to `maxEntries` filesystem entries. 50k covers a large
    /// node_modules; anything bigger reports `truncated` honestly instead of
    /// stalling the UI.
    public static func scan(_ url: URL, maxEntries: Int = 50_000) -> Result {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey, .isDirectoryKey, .totalFileAllocatedSizeKey,
        ]
        var newestContent: Date?
        var newestContentName: String?
        var newestAny: Date?
        var count = 0
        var bytes: UInt64 = 0
        var truncated = false

        // The target itself (also covers single files like a .dmg).
        if let values = try? url.resourceValues(forKeys: keys) {
            if values.isDirectory != true {
                let modified = values.contentModificationDate
                return Result(
                    newestContent: modified, newestContentName: url.lastPathComponent,
                    newestAny: modified, fileCount: 1,
                    sizeBytes: UInt64(values.totalFileAllocatedSize ?? 0), truncated: false)
            }
        }

        if let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [])
        {
            for case let child as URL in enumerator {
                if count >= maxEntries {
                    truncated = true
                    break
                }
                count += 1
                guard let values = try? child.resourceValues(forKeys: keys),
                    let modified = values.contentModificationDate
                else { continue }
                if values.isDirectory != true {
                    bytes += UInt64(values.totalFileAllocatedSize ?? 0)
                }
                if newestAny.map({ modified > $0 }) ?? true { newestAny = modified }
                // Directory mtimes churn whenever anything inside them is
                // touched — only files count as content.
                guard values.isDirectory != true, !isNoise(child) else { continue }
                if newestContent.map({ modified > $0 }) ?? true {
                    newestContent = modified
                    newestContentName = child.lastPathComponent
                }
            }
        }
        return Result(
            newestContent: newestContent, newestContentName: newestContentName,
            newestAny: newestAny, fileCount: count, sizeBytes: bytes, truncated: truncated)
    }

    /// Days since Spotlight last saw the item opened (Finder/LaunchServices
    /// opens only — CLI access never updates it). nil = no record, which
    /// means "unknown", never "unused".
    public static func spotlightLastUsedDays(_ url: URL, now: Date = .now) -> Int? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
            let value = MDItemCopyAttribute(item, kMDItemLastUsedDate),
            let date = value as? Date
        else { return nil }
        return max(0, Int(now.timeIntervalSince(date) / 86400))
    }
}

/// For tool-owned folders (~/.hermes, ~/.config/foo, App Support/Foo):
/// is the tool that owns this folder still installed? A dotfolder whose
/// owner is gone is the classic uninstall leftover — the single strongest
/// "you can delete this" signal, and the one no mtime scan can see (leftover
/// hooks keep touching dead apps' folders forever).
public struct OwnerLivenessProbe: Sendable {
    public enum Liveness: Sendable, Equatable {
        case installed(at: String)
        case missing(toolName: String)
        /// Target isn't a tool-owned folder shape — probe doesn't apply.
        case notApplicable
    }

    public let binDirectories: [String]
    public let appDirectories: [String]
    public let cellarDirectories: [String]

    /// Known folder-name → executable-name mismatches: `~/.gnupg` belongs to
    /// `gpg`, `~/.m2` to `mvn`. Extend as false "missing" reports come in.
    static let executableAliases: [String: [String]] = [
        "gnupg": ["gpg"], "m2": ["mvn"], "ssh": ["ssh"], "vscode": ["code"],
        "vscode-insiders": ["code-insiders"], "config": [],
    ]

    public init(
        binDirectories: [String]? = nil,
        appDirectories: [String]? = nil,
        cellarDirectories: [String]? = nil,
        fileManager: FileManager = .default
    ) {
        let home = fileManager.homeDirectoryForCurrentUser.path
        // GUI apps don't inherit shell PATH — enumerate the common bins
        // explicitly, including per-toolchain ones (cargo, go).
        self.binDirectories =
            binDirectories ?? [
                "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                "\(home)/.local/bin", "\(home)/bin", "\(home)/.cargo/bin", "\(home)/go/bin",
            ]
        self.appDirectories = appDirectories ?? ["/Applications", "\(home)/Applications"]
        self.cellarDirectories =
            cellarDirectories ?? [
                "/opt/homebrew/Cellar", "/usr/local/Cellar",
                "/opt/homebrew/Caskroom", "/usr/local/Caskroom",
            ]
    }

    /// The tool name a folder claims to belong to: `~/.hermes` → "hermes",
    /// `~/.config/hermes` → "hermes", `…/Application Support/Hermes` →
    /// "Hermes". nil when the folder doesn't have a tool-owned shape.
    public static func toolName(for url: URL, home: String) -> String? {
        let name = url.lastPathComponent
        let parent = url.deletingLastPathComponent().path
        // ~/.hermes — hidden dotfolder directly in home.
        if parent == home, name.hasPrefix("."), name.count > 1 {
            return String(name.dropFirst())
        }
        // ~/.config/hermes, ~/.local/share/hermes (XDG).
        if parent == "\(home)/.config" || parent == "\(home)/.local/share" { return name }
        // ~/Library/Application Support/Hermes.
        if parent.hasSuffix("/Library/Application Support"), !name.hasPrefix("com.") {
            return name
        }
        return nil
    }

    /// Looks for any installed thing named like the tool: an executable in
    /// common bin dirs, an app bundle, or a Homebrew formula. Conservative
    /// on the "missing" side by design — a hit anywhere means "installed",
    /// because tools like docker own ~/.docker via Docker.app, not PATH.
    public func check(toolName: String) -> Liveness {
        let fm = FileManager.default
        let lower = toolName.lowercased()
        // Alias-only names ("config") never resolve to an owner.
        if let aliases = Self.executableAliases[lower], aliases.isEmpty {
            return .notApplicable
        }
        let candidates = [lower] + (Self.executableAliases[lower] ?? [])
        for bin in binDirectories {
            for name in candidates {
                let candidate = "\(bin)/\(name)"
                if fm.isExecutableFile(atPath: candidate) {
                    return .installed(at: candidate)
                }
            }
        }
        for appDir in appDirectories {
            guard let apps = try? fm.contentsOfDirectory(atPath: appDir) else {
                continue
            }
            // Prefix match: ~/.docker ↔ Docker.app, ~/.arc ↔ Arc.app,
            // "Visual Studio Code" ↔ code? — name-based matching is fuzzy;
            // prefix keeps it usefully loose in the "installed" direction.
            for app in apps where app.lowercased().hasPrefix(lower) && app.hasSuffix(".app") {
                return .installed(at: "\(appDir)/\(app)")
            }
        }
        for cellar in cellarDirectories
        where fm.fileExists(atPath: "\(cellar)/\(lower)") {
            return .installed(at: "\(cellar)/\(lower)")
        }
        return .missing(toolName: toolName)
    }

    public func liveness(for url: URL, home: String) -> Liveness {
        guard let name = Self.toolName(for: url, home: home) else { return .notApplicable }
        return check(toolName: name)
    }
}

/// Greps shell history for evidence a CLI tool is still being run — the
/// usage log macOS doesn't keep, hiding in ~/.zsh_history. Positive evidence
/// only: a hit proves use; absence proves nothing (scripts, Makefiles and
/// GUI launches never reach history, and HISTSIZE caps how far back it goes).
public struct ShellHistoryProbe: Sendable {
    public struct Hit: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            /// The tool itself was invoked — strong evidence of use.
            case ran
            /// The target path merely appeared in a command line (a cd, an
            /// old export) — proves the user knows the folder, not that its
            /// tool still runs.
            case mentioned
        }

        public let command: String
        public let kind: Kind
        public let count: Int
        /// From zsh extended history timestamps; nil for plain-format files.
        public let lastUsed: Date?
    }

    public let historyFiles: [URL]

    public init(historyFiles: [URL]? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.historyFiles =
            historyFiles ?? [
                home.appendingPathComponent(".zsh_history"),
                home.appendingPathComponent(".bash_history"),
            ]
    }

    /// Command names worth searching for a target: executables in its bin/
    /// (the Cellar/venv shape) or, when the target itself holds executables,
    /// their names.
    public static func commandNames(
        for target: URL, fileManager: FileManager = .default, cap: Int = 200
    ) -> Set<String> {
        var names: Set<String> = []
        for binDir in [target.appendingPathComponent("bin"), target] {
            guard let children = try? fileManager.contentsOfDirectory(
                at: binDir, includingPropertiesForKeys: [.isExecutableKey, .isDirectoryKey])
            else { continue }
            for child in children {
                guard names.count < cap else { break }
                let values = try? child.resourceValues(
                    forKeys: [.isExecutableKey, .isDirectoryKey])
                if values?.isExecutable == true && values?.isDirectory != true {
                    names.insert(child.lastPathComponent)
                }
            }
        }
        return names
    }

    /// Scans history for invocations of `names` or lines mentioning
    /// `targetPath` directly. Returns hits sorted most-recent/most-used first.
    public func hits(names: Set<String>, targetPath: String) -> [Hit] {
        var byCommand: [String: (kind: Hit.Kind, count: Int, last: Date?)] = [:]

        for file in historyFiles {
            guard let data = try? Data(contentsOf: file) else { continue }
            // zsh history is not valid UTF-8 when commands contained non-ASCII
            // (it "metafies" bytes) — decode lossily rather than dropping the file.
            let content = String(decoding: data, as: UTF8.self)
            for rawLine in content.split(separator: "\n") {
                let (command, timestamp) = Self.parseHistoryLine(String(rawLine))
                guard !command.isEmpty else { continue }
                guard
                    let match = Self.match(
                        command: command, names: names, targetPath: targetPath)
                else { continue }
                let existing = byCommand[match.name] ?? (match.kind, 0, nil)
                let newLast = [existing.last, timestamp].compactMap { $0 }.max()
                // A `ran` sighting upgrades an earlier `mentioned` one.
                let kind: Hit.Kind = (existing.kind == .ran || match.kind == .ran)
                    ? .ran : .mentioned
                byCommand[match.name] = (kind, existing.count + 1, newLast)
            }
        }

        return byCommand.map {
            Hit(command: $0.key, kind: $0.value.kind, count: $0.value.count, lastUsed: $0.value.last)
        }
        .sorted {
            switch ($0.lastUsed, $1.lastUsed) {
            case let (a?, b?): return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return $0.count > $1.count
            }
        }
    }

    /// zsh extended format `: 1720000000:0;cmd args` or plain `cmd args`.
    static func parseHistoryLine(_ line: String) -> (command: String, timestamp: Date?) {
        if line.hasPrefix(": "), let semicolon = line.firstIndex(of: ";") {
            let meta = line[line.index(line.startIndex, offsetBy: 2)..<semicolon]
            let ts = meta.split(separator: ":").first.flatMap { Double($0) }
            let command = String(line[line.index(after: semicolon)...])
            return (command, ts.map { Date(timeIntervalSince1970: $0) })
        }
        return (line, nil)
    }

    /// How a command line relates to the target: the first token (after
    /// `sudo`/env assignments) being one of the target's executables is a
    /// `ran`; the target path merely appearing anywhere is a `mentioned`.
    static func match(
        command: String, names: Set<String>, targetPath: String
    ) -> (name: String, kind: Hit.Kind)? {
        var tokens = command.split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        while let first = tokens.first, first == "sudo" || first.contains("=") {
            tokens.removeFirst()
        }
        if let first = tokens.first {
            let base = (first as NSString).lastPathComponent
            if names.contains(base) { return (base, .ran) }
        }
        if !targetPath.isEmpty, command.contains(targetPath) {
            return ((targetPath as NSString).lastPathComponent, .mentioned)
        }
        return nil
    }
}
