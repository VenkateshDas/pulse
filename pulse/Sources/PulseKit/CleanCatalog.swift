import Foundation

public struct CleanTarget: Sendable {
    public let rel: String
    public let category: String
    public let grade: SafetyGrade
    public let detail: String
    public let expand: Bool
}

public enum CleanCatalog {
    /// Safe, common caches and safe developer junk.
    public static let knownTargets: [CleanTarget] = [
        CleanTarget(rel: "Library/Caches", category: "App caches", grade: .safe,
                    detail: "regenerated automatically on next launch", expand: true),
        CleanTarget(rel: "Library/Logs", category: "App logs", grade: .safe,
                    detail: "only useful for active debugging", expand: true),
        CleanTarget(rel: "Library/Developer/Xcode/DerivedData", category: "Developer junk", grade: .safe,
                    detail: "next build is a clean build — no source touched", expand: false),
        CleanTarget(rel: "Library/Developer/Xcode/Archives", category: "Developer junk", grade: .careful,
                    detail: "needed only to re-symbolicate or re-submit past builds", expand: false),
        CleanTarget(rel: ".npm", category: "Developer junk", grade: .safe,
                    detail: "package download cache — refilled on next npm install", expand: false),
        CleanTarget(rel: ".cache", category: "Developer junk", grade: .safe,
                    detail: "pip wheels and CLI tool caches — regenerated on next install", expand: false),
        CleanTarget(rel: "Library/Application Support/MobileSync/Backup", category: "iOS backups", grade: .review,
                    detail: "full device backups — delete only with a current backup elsewhere", expand: false),
        CleanTarget(rel: ".Trash", category: "Trash", grade: .safe,
                    detail: "already deleted — cleaning via Pulse keeps 7-day restore", expand: false)
    ]

    /// Heavier developer environments and AI tool caches.
    public static let developerTargets: [CleanTarget] = [
        CleanTarget(rel: "Library/Caches/Homebrew", category: "Developer junk", grade: .safe,
                    detail: "Homebrew download cache — refilled on next brew install", expand: false),
        CleanTarget(rel: "Library/Developer/CoreSimulator/Caches", category: "Developer junk", grade: .safe,
                    detail: "Xcode simulator caches — rebuilt by Xcode automatically", expand: false),
        CleanTarget(rel: "Library/Developer/CoreSimulator/Devices", category: "Developer junk", grade: .careful,
                    detail: "simulator devices and their data — recreate from Xcode if removed", expand: false),
        CleanTarget(rel: "Library/Containers/com.docker.docker/Data/vms", category: "Developer junk", grade: .review,
                    detail: "Docker VM disk — deleting loses all containers, images, and volumes", expand: false),
        
        // AI tooling (Pulse exclusive)
        CleanTarget(rel: ".claude", category: "AI tool junk", grade: .safe, detail: "Claude local cache", expand: false),
        CleanTarget(rel: ".codex", category: "AI tool junk", grade: .safe, detail: "Codex local cache", expand: false),
        CleanTarget(rel: ".cursor", category: "AI tool junk", grade: .safe, detail: "Cursor local cache", expand: false),
        CleanTarget(rel: ".copilot/pkg/universal", category: "AI tool junk", grade: .safe, detail: "Copilot universal cache", expand: false),
        CleanTarget(rel: ".gemini/antigravity", category: "AI tool junk", grade: .safe, detail: "Gemini Antigravity cache", expand: false),
        CleanTarget(rel: ".gemini/tmp", category: "AI tool junk", grade: .safe, detail: "Gemini tmp space", expand: false),
        CleanTarget(rel: ".local/share/claude/versions", category: "AI tool junk", grade: .safe, detail: "Claude versions", expand: false),

        // General Dev Caches
        CleanTarget(rel: "Library/Caches/go-build", category: "Developer junk", grade: .safe, detail: "Go build cache", expand: false),
        CleanTarget(rel: "Library/Caches/pip", category: "Developer junk", grade: .safe, detail: "pip cache", expand: false),
        CleanTarget(rel: "Library/Caches/mise", category: "Developer junk", grade: .safe, detail: "mise cache", expand: false),
        CleanTarget(rel: ".bun/install/cache", category: "Developer junk", grade: .safe, detail: "Bun cache", expand: false),
        CleanTarget(rel: ".cache/uv", category: "Developer junk", grade: .safe, detail: "uv cache", expand: false),
        CleanTarget(rel: ".conda/pkgs", category: "Developer junk", grade: .safe, detail: "Conda packages", expand: false),
        CleanTarget(rel: ".rustup/toolchains", category: "Developer junk", grade: .careful, detail: "Rust toolchains", expand: false),
        CleanTarget(rel: "go/pkg/mod", category: "Developer junk", grade: .safe, detail: "Go modules", expand: false),
        CleanTarget(rel: ".gradle/caches", category: "Developer junk", grade: .safe, detail: "Gradle caches", expand: false),
        CleanTarget(rel: ".orbstack", category: "Developer junk", grade: .careful, detail: "OrbStack cache", expand: false)
    ]
}
