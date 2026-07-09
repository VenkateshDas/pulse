import Foundation

/// A recognized folder/file species: what it is in plain English, who made
/// it, and — the part no other cleaner ships — whether deleting it is
/// recoverable and what the recovery actually costs.
public struct FolderSpecies: Sendable, Equatable {
    public let id: String
    public let name: String
    public let explanation: String
    public let ownerTool: String?
    public let regenerable: Bool
    /// Command or action that brings the data back, nil when regenerable
    /// is false or regeneration is automatic.
    public let regenCommand: String?
    /// Honest cost of regeneration ("needs network", "only from the device").
    public let regenCaveat: String?

    public init(
        id: String, name: String, explanation: String, ownerTool: String? = nil,
        regenerable: Bool, regenCommand: String? = nil, regenCaveat: String? = nil
    ) {
        self.id = id
        self.name = name
        self.explanation = explanation
        self.ownerTool = ownerTool
        self.regenerable = regenerable
        self.regenCommand = regenCommand
        self.regenCaveat = regenCaveat
    }
}

/// Identifies what a folder or file *is* from marker files and path shape —
/// the difference between "473 MB folder named .venv" and "Python virtual
/// environment, regenerable with one command". Rules are ordered specific →
/// generic; first match wins. Seeded from the folder types kondo, DevCleaner
/// and CleanMyMac recognize, plus regenerability metadata none of them carry.
public enum FingerprintCatalog {
    /// One recognizer: returns the species when the URL matches.
    typealias Rule = @Sendable (URL, FileManager) -> FolderSpecies?

    public static func identify(
        _ url: URL, fileManager: FileManager = .default
    ) -> FolderSpecies? {
        for rule in rules {
            if let species = rule(url, fileManager) { return species }
        }
        return nil
    }

    private static func hasChild(_ url: URL, _ name: String, _ fm: FileManager) -> Bool {
        fm.fileExists(atPath: url.appendingPathComponent(name).path)
    }

    private static func hasSibling(_ url: URL, _ name: String, _ fm: FileManager) -> Bool {
        fm.fileExists(
            atPath: url.deletingLastPathComponent().appendingPathComponent(name).path)
    }

    static let rules: [Rule] = [
        // Python virtual environment — pyvenv.cfg is definitive.
        { url, fm in
            guard hasChild(url, "pyvenv.cfg", fm) else { return nil }
            return FolderSpecies(
                id: "python-venv", name: "Python virtual environment",
                explanation:
                    "Per-project Python packages. The project's code is NOT in here.",
                ownerTool: "Python", regenerable: true,
                regenCommand:
                    "python3 -m venv \(url.lastPathComponent) && pip install -r requirements.txt",
                regenCaveat: "needs network; requires the project's requirements file")
        },
        // Conda installation root (miniforge/miniconda) — has envs/ + conda-meta/.
        { url, fm in
            guard hasChild(url, "conda-meta", fm), hasChild(url, "envs", fm) else { return nil }
            return FolderSpecies(
                id: "conda-root", name: "Conda installation (Miniforge/Miniconda)",
                explanation:
                    "A full conda distribution including every environment created inside it.",
                ownerTool: "Conda", regenerable: true,
                regenCommand: "reinstall Miniforge, then conda env create per environment",
                regenCaveat: "environments not exported to environment.yml are lost")
        },
        // Single conda environment.
        { url, fm in
            guard hasChild(url, "conda-meta", fm) else { return nil }
            return FolderSpecies(
                id: "conda-env", name: "Conda environment",
                explanation: "One conda environment's packages. Project code is NOT in here.",
                ownerTool: "Conda", regenerable: true,
                regenCommand: "conda env create -f environment.yml",
                regenCaveat: "needs network; requires an exported environment.yml")
        },
        // node_modules with the owning package.json next to it.
        { url, fm in
            guard url.lastPathComponent == "node_modules", hasSibling(url, "package.json", fm)
            else { return nil }
            return FolderSpecies(
                id: "node-modules", name: "Node.js dependencies (node_modules)",
                explanation: "Installed npm packages for the project one level up.",
                ownerTool: "npm/yarn/pnpm", regenerable: true,
                regenCommand: "npm install",
                regenCaveat: "needs network; exact versions need the lockfile")
        },
        // Rust build dir.
        { url, fm in
            guard url.lastPathComponent == "target", hasSibling(url, "Cargo.toml", fm)
            else { return nil }
            return FolderSpecies(
                id: "cargo-target", name: "Rust build artifacts (target)",
                explanation: "Compiled output for the Rust project one level up.",
                ownerTool: "Cargo", regenerable: true, regenCommand: "cargo build",
                regenCaveat: "next build recompiles from scratch (slow once)")
        },
        // SwiftPM build dir.
        { url, fm in
            guard url.lastPathComponent == ".build", hasSibling(url, "Package.swift", fm)
            else { return nil }
            return FolderSpecies(
                id: "swiftpm-build", name: "Swift package build artifacts (.build)",
                explanation: "Compiled output for the Swift package one level up.",
                ownerTool: "SwiftPM", regenerable: true, regenCommand: "swift build",
                regenCaveat: "next build recompiles from scratch")
        },
        // Xcode DerivedData.
        { url, _ in
            guard url.path.contains("/DerivedData/") || url.lastPathComponent == "DerivedData"
            else { return nil }
            return FolderSpecies(
                id: "derived-data", name: "Xcode DerivedData",
                explanation: "Xcode's build cache and indexes.",
                ownerTool: "Xcode", regenerable: true,
                regenCommand: nil,
                regenCaveat: "Xcode recreates it automatically; next builds are slower once")
        },
        // Xcode archives — dSYMs needed for crash symbolication; not regenerable.
        { url, _ in
            guard url.path.contains("/Xcode/Archives") else { return nil }
            return FolderSpecies(
                id: "xcode-archives", name: "Xcode app archive",
                explanation:
                    "Built app releases with debug symbols — needed to symbolicate crash reports from shipped builds.",
                ownerTool: "Xcode", regenerable: false)
        },
        // iOS simulator runtimes/devices.
        { url, _ in
            guard url.path.contains("/CoreSimulator/") else { return nil }
            return FolderSpecies(
                id: "ios-simulator", name: "iOS Simulator data",
                explanation: "Simulator devices and runtimes.",
                ownerTool: "Xcode", regenerable: true,
                regenCommand: "xcrun simctl delete unavailable",
                regenCaveat: "runtimes re-download on demand (large)")
        },
        // iPhone/iPad backups — regenerable ONLY from the device itself.
        { url, _ in
            guard url.path.contains("/MobileSync/Backup") else { return nil }
            return FolderSpecies(
                id: "ios-backup", name: "iPhone/iPad backup",
                explanation: "A device backup made by Finder/iTunes.",
                ownerTool: "Finder", regenerable: false,
                regenCaveat: "can only be recreated by backing up the device again — if the device is gone, so is the data")
        },
        // Homebrew Cellar formula.
        { url, _ in
            for prefix in ["/opt/homebrew/Cellar/", "/usr/local/Cellar/"]
            where url.path.hasPrefix(prefix) {
                let rest = url.path.dropFirst(prefix.count)
                guard let formula = rest.split(separator: "/").first else { continue }
                return FolderSpecies(
                    id: "brew-formula", name: "Homebrew package (\(formula))",
                    explanation: "An installed Homebrew formula.",
                    ownerTool: "Homebrew", regenerable: true,
                    regenCommand: "brew reinstall \(formula)",
                    regenCaveat: "prefer `brew uninstall \(formula)` over deleting the folder — deleting by hand leaves brew's records inconsistent")
            }
            return nil
        },
        // Docker's disk image — images regenerable, volumes are NOT.
        { url, _ in
            guard url.lastPathComponent == "Docker.raw" || url.path.contains("com.docker.docker")
            else { return nil }
            return FolderSpecies(
                id: "docker-data", name: "Docker data",
                explanation:
                    "Docker's images, containers AND volumes live in this one file/folder.",
                ownerTool: "Docker", regenerable: false,
                regenCaveat: "images re-pull from registries, but named volumes (databases!) are only here — use `docker system prune` instead of deleting")
        },
        // Gradle / Maven dependency caches.
        { url, _ in
            guard url.path.contains("/.gradle/caches") else { return nil }
            return FolderSpecies(
                id: "gradle-cache", name: "Gradle cache",
                explanation: "Downloaded dependencies and build cache for Gradle projects.",
                ownerTool: "Gradle", regenerable: true,
                regenCaveat: "re-downloads on next build; needs network")
        },
        { url, _ in
            guard url.path.contains("/.m2/repository") else { return nil }
            return FolderSpecies(
                id: "maven-repo", name: "Maven local repository",
                explanation: "Downloaded dependencies for Maven projects.",
                ownerTool: "Maven", regenerable: true,
                regenCaveat: "re-downloads on next build; needs network")
        },
        // npm global cache.
        { url, fm in
            guard url.lastPathComponent == ".npm",
                fm.homeDirectoryForCurrentUser.appendingPathComponent(".npm").path == url.path
                    || url.path.hasSuffix("/.npm")
            else { return nil }
            return FolderSpecies(
                id: "npm-cache", name: "npm cache",
                explanation: "npm's download cache.",
                ownerTool: "npm", regenerable: true,
                regenCaveat: "re-downloads on demand")
        },
        // Anything under a Caches directory.
        { url, _ in
            guard url.path.contains("/Library/Caches/") || url.lastPathComponent == "Caches"
            else { return nil }
            return FolderSpecies(
                id: "cache", name: "Application cache",
                explanation: "Cached data an app can rebuild on its own.",
                regenerable: true,
                regenCaveat: "the owning app recreates it as needed")
        },
        // Installer images.
        { url, _ in
            let ext = url.pathExtension.lowercased()
            guard ["dmg", "pkg", "iso", "xip"].contains(ext) else { return nil }
            return FolderSpecies(
                id: "installer", name: "Installer image (.\(ext))",
                explanation:
                    "A downloaded installer. If the app is already installed, this copy does nothing.",
                regenerable: true,
                regenCaveat: "re-download from the original source; old versions may no longer be offered")
        },
        // Photos library — irreplaceable.
        { url, _ in
            guard ["photoslibrary", "migratedphotolibrary"].contains(
                url.pathExtension.lowercased())
            else { return nil }
            return FolderSpecies(
                id: "photos-library", name: "Photos library",
                explanation: "Your photo library. Originals live inside this bundle.",
                ownerTool: "Photos", regenerable: false,
                regenCaveat: "irreplaceable unless fully synced to iCloud Photos")
        },
        // Git working copy — recoverable only if pushed.
        { url, fm in
            guard hasChild(url, ".git", fm) else { return nil }
            return FolderSpecies(
                id: "git-project", name: "Git project working copy",
                explanation: "A source-code project under version control.",
                ownerTool: "Git", regenerable: false,
                regenCaveat: "re-cloneable ONLY if every branch and uncommitted change is pushed — check before deleting")
        },
    ]
}
