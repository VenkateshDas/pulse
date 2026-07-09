import CoreServices
import Foundation

/// Bounded "how dead is this tree" walk: newest modification date anywhere
/// inside, plus size and file count. mtime only — APFS atime is unreliable
/// (noatime mounts, relatime semantics), so it is never read.
public enum StalenessProbe {
    public struct Result: Sendable, Equatable {
        public let newestModified: Date?
        public let fileCount: Int
        public let sizeBytes: UInt64
        /// True when the walk stopped at the entry cap — dates are then a
        /// lower bound, not the whole truth.
        public let truncated: Bool
    }

    /// Walks up to `maxEntries` filesystem entries. 50k covers a large
    /// node_modules; anything bigger reports `truncated` honestly instead of
    /// stalling the UI.
    public static func scan(_ url: URL, maxEntries: Int = 50_000) -> Result {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey, .isDirectoryKey, .totalFileAllocatedSizeKey,
        ]
        var newest: Date?
        var count = 0
        var bytes: UInt64 = 0
        var truncated = false

        // The target itself (also covers single files like a .dmg).
        if let values = try? url.resourceValues(forKeys: keys) {
            newest = values.contentModificationDate
            if values.isDirectory != true {
                return Result(
                    newestModified: newest, fileCount: 1,
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
                guard let values = try? child.resourceValues(forKeys: keys) else { continue }
                if let modified = values.contentModificationDate,
                    newest.map({ modified > $0 }) ?? true
                {
                    newest = modified
                }
                if values.isDirectory != true {
                    bytes += UInt64(values.totalFileAllocatedSize ?? 0)
                }
            }
        }
        return Result(
            newestModified: newest, fileCount: count, sizeBytes: bytes, truncated: truncated)
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

/// Greps shell history for evidence a CLI tool is still being run — the
/// usage log macOS doesn't keep, hiding in ~/.zsh_history. Positive evidence
/// only: a hit proves use; absence proves nothing (scripts, Makefiles and
/// GUI launches never reach history, and HISTSIZE caps how far back it goes).
public struct ShellHistoryProbe: Sendable {
    public struct Hit: Sendable, Equatable {
        public let command: String
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
        var byCommand: [String: (count: Int, last: Date?)] = [:]

        for file in historyFiles {
            guard let data = try? Data(contentsOf: file) else { continue }
            // zsh history is not valid UTF-8 when commands contained non-ASCII
            // (it "metafies" bytes) — decode lossily rather than dropping the file.
            let content = String(decoding: data, as: UTF8.self)
            for rawLine in content.split(separator: "\n") {
                let (command, timestamp) = Self.parseHistoryLine(String(rawLine))
                guard !command.isEmpty else { continue }
                guard
                    let name = Self.matchedName(
                        command: command, names: names, targetPath: targetPath)
                else { continue }
                let existing = byCommand[name] ?? (0, nil)
                let newLast = [existing.last, timestamp].compactMap { $0 }.max()
                byCommand[name] = (existing.count + 1, newLast)
            }
        }

        return byCommand.map { Hit(command: $0.key, count: $0.value.count, lastUsed: $0.value.last) }
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

    /// The history name a command line counts as: its first token (after
    /// `sudo`/env assignments) when that token is one of `names`, or the
    /// token's basename for full-path invocations; falls back to a raw
    /// substring match on the target path anywhere in the line.
    static func matchedName(
        command: String, names: Set<String>, targetPath: String
    ) -> String? {
        var tokens = command.split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        while let first = tokens.first, first == "sudo" || first.contains("=") {
            tokens.removeFirst()
        }
        if let first = tokens.first {
            let base = (first as NSString).lastPathComponent
            if names.contains(base) { return base }
        }
        if !targetPath.isEmpty, command.contains(targetPath) {
            return (targetPath as NSString).lastPathComponent
        }
        return nil
    }
}
