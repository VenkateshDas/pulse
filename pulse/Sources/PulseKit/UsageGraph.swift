import Foundation

/// The kind of evidence linking a referrer to a target path.
public enum ReferenceSignal: String, Codable, Sendable, CaseIterable {
    case homebrew, textRef, dylib, symlink
}

/// One piece of evidence that `source` depends on `target`.
public struct UsageEdge: Sendable, Codable, Identifiable, Equatable {
    public var id: String { "\(signal.rawValue)|\(source.path)|\(target.path)|\(detail)" }
    public let source: URL
    public let target: URL
    public let signal: ReferenceSignal
    /// Human-readable evidence, e.g. ".zshrc:12" or "Installed runtime dependency: python@3.11".
    public let detail: String

    public init(source: URL, target: URL, signal: ReferenceSignal, detail: String) {
        self.source = source
        self.target = target
        self.signal = signal
        self.detail = detail
    }
}

/// Per-signal JSON cache so a whole-disk crawl only happens once per signal
/// until the user asks for a Rescan. Each signal is cached independently —
/// receipt and binary header scans can be reused independently; there is no
/// reason a Rescan of one should throw away the other three.
public struct UsageIndexCache: Sendable {
    private struct Entry: Codable {
        let edges: [UsageEdge]
        let builtAt: Date
    }

    public let directory: URL

    public init(
        directory: URL = UsageIndexCache.defaultDirectory()
    ) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Pulse/usage-cache-native-v1")
    }

    private func fileURL(for signal: ReferenceSignal) -> URL {
        directory.appendingPathComponent("\(signal.rawValue).json")
    }

    /// All cached edges for `signal`, or nil when there's no cache yet.
    public func load(_ signal: ReferenceSignal) -> [UsageEdge]? {
        guard let data = try? Data(contentsOf: fileURL(for: signal)),
            let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }
        return entry.edges
    }

    /// Replaces the cached edges for `signal` with a freshly crawled set.
    public func store(_ signal: ReferenceSignal, edges: [UsageEdge]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Entry(edges: edges, builtAt: .now)) else { return }
        try? data.write(to: fileURL(for: signal), options: .atomic)
    }
}

/// Finds what on disk references a given file or folder — the inverse of
/// `UninstallScanner` (which starts from an app and finds its leftovers).
/// Each signal is a weak, static clue on its own; combined they answer
/// "is this folder still needed" well enough to guide a cleanup decision.
/// Not a guarantee: none of these signals see runtime-only references
/// (e.g. a path built dynamically at execution time).
public actor UsageGraphScanner {
    private let cache: UsageIndexCache
    private let fileManager: FileManager
    private let home: String

    /// Root paths for each collector, `~` expanded against `home`. Defaults
    /// to real system locations; tests inject temp-directory fixtures instead.
    private let brewPrefixes: [String]
    private let textRefFiles: [String]
    private let plistDirs: [String]
    private let appDirectories: [String]
    private let binDirectories: [String]
    private let symlinkRoots: [String]

    public init(
        cache: UsageIndexCache = UsageIndexCache(),
        fileManager: FileManager = .default,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        brewPrefixes: [String] = ["/opt/homebrew", "/usr/local"],
        textRefFiles: [String] = ["~/.zshrc", "~/.zprofile", "~/.bash_profile", "~/.profile", "~/.bashrc"],
        plistDirs: [String] = ["~/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"],
        appDirectories: [String] = ["/Applications", "~/Applications"],
        binDirectories: [String] = ["/opt/homebrew/bin", "/usr/local/bin"],
        symlinkRoots: [String] = ["/opt/homebrew", "/usr/local", "~/Applications", "~/bin", "~/.local"]
    ) {
        self.cache = cache
        self.fileManager = fileManager
        self.home = home
        self.brewPrefixes = brewPrefixes
        self.textRefFiles = textRefFiles
        self.plistDirs = plistDirs
        self.appDirectories = appDirectories
        self.binDirectories = binDirectories
        self.symlinkRoots = symlinkRoots
    }

    private func expand(_ path: String) -> String {
        path.hasPrefix("~") ? path.replacingOccurrences(of: "~", with: home) : path
    }

    /// Every edge pointing at `target`, one crawl per signal unless cached
    /// (or explicitly forced via `forceRescan`).
    public func referrers(
        for target: URL, forceRescan: Set<ReferenceSignal> = []
    ) async -> [UsageEdge] {
        var all: [UsageEdge] = []
        for signal in ReferenceSignal.allCases {
            if !forceRescan.contains(signal), let cached = cache.load(signal) {
                all += cached.filter { matches($0.target, target) }
                continue
            }
            let fresh = await crawl(signal)
            cache.store(signal, edges: fresh)
            all += fresh.filter { matches($0.target, target) }
        }
        return all
    }

    /// True when `edgeTarget` is `queried` itself or falls inside it — an
    /// edge's target is often a specific file (a Mach-O load path, a resolved
    /// symlink destination) one or more levels under the folder being asked
    /// about.
    private func matches(_ edgeTarget: URL, _ queried: URL) -> Bool {
        edgeTarget.path == queried.path || edgeTarget.path.hasPrefix(queried.path + "/")
    }

    private func crawl(_ signal: ReferenceSignal) async -> [UsageEdge] {
        switch signal {
        case .homebrew: return homebrewEdges()
        case .textRef: return textRefEdges()
        case .dylib: return dylibEdges()
        case .symlink: return symlinkEdges()
        }
    }

    // MARK: - Homebrew

    /// Installed runtime dependencies come from keg receipts, without invoking brew.
    private func homebrewEdges() -> [UsageEdge] {
        var out: [UsageEdge] = []
        for prefix in brewPrefixes {
            let cellar = URL(fileURLWithPath: "\(prefix)/Cellar")
            guard let formulae = try? fileManager.contentsOfDirectory(at: cellar, includingPropertiesForKeys: nil) else { continue }
            for formula in formulae {
                guard let versions = try? fileManager.contentsOfDirectory(at: formula, includingPropertiesForKeys: nil) else { continue }
                var dependencies = Set<String>()
                for version in versions {
                    let receipt = version.appendingPathComponent("INSTALL_RECEIPT.json")
                    guard let values = try? receipt.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                          values.isRegularFile == true, let size = values.fileSize, size <= 1_048_576,
                          let data = try? Data(contentsOf: receipt),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let runtime = json["runtime_dependencies"] as? [[String: Any]] else { continue }
                    for dependency in runtime {
                        guard let fullName = dependency["full_name"] as? String,
                              let name = fullName.split(separator: "/").last.map(String.init),
                              name != ".", name != ".." else { continue }
                        dependencies.insert(name)
                    }
                }
                for dependency in dependencies {
                    let target = cellar.appendingPathComponent(dependency)
                    guard fileManager.fileExists(atPath: target.path) else { continue }
                    out.append(UsageEdge(
                        source: URL(fileURLWithPath: "\(prefix)/opt/\(formula.lastPathComponent)"),
                        target: target, signal: .homebrew,
                        detail: "Installed runtime dependency: \(formula.lastPathComponent)"))
                }
            }
        }
        return out
    }

    // MARK: - Text references

    /// Greps dotfiles and launchd plists for the literal path string. Static
    /// and cheap, but only catches explicit textual references.
    private func textRefEdges() -> [UsageEdge] {
        var out: [UsageEdge] = []

        for rel in textRefFiles {
            let path = expand(rel)
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for (index, line) in content.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
            {
                for target in extractPaths(fromLine: String(line)) {
                    out.append(
                        UsageEdge(
                            source: URL(fileURLWithPath: path), target: target, signal: .textRef,
                            detail: "\((path as NSString).lastPathComponent):\(index + 1)"))
                }
            }
        }

        for dirRel in plistDirs {
            let dir = URL(fileURLWithPath: expand(dirRel))
            guard let plists = try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)
            else { continue }
            for plistURL in plists where plistURL.pathExtension == "plist" {
                guard let plist = UninstallScanner.readLaunchPlist(plistURL) else { continue }
                let strings = plistStrings(plist)
                for candidate in strings {
                    for target in extractPaths(fromLine: candidate) {
                        out.append(
                            UsageEdge(
                                source: plistURL, target: target, signal: .textRef,
                                detail: "\(plistURL.lastPathComponent) (LaunchAgent/Daemon)"))
                    }
                }
            }
        }
        return out
    }

    /// Flattens a plist's string values (Program, ProgramArguments,
    /// EnvironmentVariables) into a searchable list.
    private func plistStrings(_ plist: [String: Any]) -> [String] {
        var out: [String] = []
        if let program = plist["Program"] as? String { out.append(program) }
        if let args = plist["ProgramArguments"] as? [String] { out += args }
        if let env = plist["EnvironmentVariables"] as? [String: String] { out += Array(env.values) }
        return out
    }

    /// Every absolute-path-shaped token in `line` (split on whitespace and
    /// the punctuation that commonly surrounds a path in shell/plist syntax:
    /// quotes, `:` PATH separators, `;`, `$`). A line like
    /// `export PATH="/opt/x/bin:$PATH"` yields `/opt/x/bin`, not the whole line.
    private func extractPaths(fromLine line: String) -> [URL] {
        let separators = CharacterSet(charactersIn: " \t\"':;()$`").union(.whitespaces)
        return line.components(separatedBy: separators)
            .filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Dylib linkage

    /// Bounded native header reads; inspected executables are never run.
    private func dylibEdges() -> [UsageEdge] {
        binariesToInspect().flatMap { binary in
            MachODependencies.paths(in: binary).map { path in
                UsageEdge(source: binary, target: URL(fileURLWithPath: path),
                          signal: .dylib, detail: "Mach-O dependency: \(binary.path)")
            }
        }
    }

    /// Main executables of top-level `.app` bundles, plus direct children of
    /// the Homebrew/local `bin` directories. Deliberately shallow — a full
    /// recursive binary sweep would be far too slow for an on-demand lookup.
    private func binariesToInspect() -> [URL] {
        var out: [URL] = []
        for root in appDirectories.map(expand) {
            guard let apps = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for app in apps where app.hasSuffix(".app") {
                let appURL = URL(fileURLWithPath: root).appendingPathComponent(app)
                guard let info = UninstallScanner.readLaunchPlist(
                    appURL.appendingPathComponent("Contents/Info.plist")),
                    let exe = info["CFBundleExecutable"] as? String
                else { continue }
                out.append(appURL.appendingPathComponent("Contents/MacOS/\(exe)"))
            }
        }
        for root in binDirectories.map(expand) {
            guard let bins = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            out += bins.map { URL(fileURLWithPath: root).appendingPathComponent($0) }
        }
        return out
    }

    // MARK: - Symlinks

    /// Walks common install roots for symlinks whose resolved destination
    /// falls under any known Cellar/conda path — the classic Homebrew
    /// `opt/<formula>` → `Cellar/<formula>/<version>` indirection.
    private func symlinkEdges() -> [UsageEdge] {
        var out: [UsageEdge] = []
        for rootRel in symlinkRoots {
            walkSymlinks(under: URL(fileURLWithPath: expand(rootRel)), depth: 3, into: &out)
        }
        return out
    }

    private func walkSymlinks(under dir: URL, depth: Int, into out: inout [UsageEdge]) {
        guard depth > 0,
            let children = try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        else { return }
        for child in children {
            let values = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if values?.isSymbolicLink == true {
                guard let dest = try? fileManager.destinationOfSymbolicLink(atPath: child.path)
                else { continue }
                let resolved =
                    dest.hasPrefix("/")
                    ? dest : child.deletingLastPathComponent().appendingPathComponent(dest).path
                out.append(
                    UsageEdge(
                        source: child, target: URL(fileURLWithPath: resolved), signal: .symlink,
                        detail: "symlink: \(child.path) → \(resolved)"))
            } else if values?.isDirectory == true {
                walkSymlinks(under: child, depth: depth - 1, into: &out)
            }
        }
    }
}
