# Graph Report - pulse  (2026-06-13)

## Corpus Check
- 79 files · ~314,710 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 918 nodes · 1818 edges · 56 communities (53 shown, 3 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 63 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]

## God Nodes (most connected - your core abstractions)
1. `View` - 62 edges
2. `SmartScanner` - 29 edges
3. `CleanModel` - 27 edges
4. `CleanScheduler` - 22 edges
5. `DashboardModel` - 21 edges
6. `MonitorModel` - 21 edges
7. `HealthModel` - 18 edges
8. `StorageModel` - 18 edges
9. `SafetyVault` - 18 edges
10. `makeSnapshot()` - 18 edges

## Surprising Connections (you probably didn't know these)
- `writeFile()` --calls--> `Data`  [INFERRED]
  Tests/PulseKitTests/CleanTests.swift → .build/arm64-apple-macosx/debug/PulsePackageTests.derived/runner.swift
- `writeFile()` --calls--> `Data`  [INFERRED]
  Tests/PulseKitTests/StorageTests.swift → .build/arm64-apple-macosx/debug/PulsePackageTests.derived/runner.swift
- `AlertsSection` --references--> `View`  [EXTRACTED]
  Sources/Pulse/Views/AlertsSection.swift → Sources/Pulse/PulseApp.swift
- `CleanView` --references--> `View`  [EXTRACTED]
  Sources/Pulse/Views/CleanView.swift → Sources/Pulse/PulseApp.swift
- `MonitorView` --references--> `View`  [EXTRACTED]
  Sources/Pulse/Views/MonitorView.swift → Sources/Pulse/PulseApp.swift

## Import Cycles
- None detected.

## Communities (56 total, 3 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.20
Nodes (11): Bundle, Encodable, NSObject, SwiftPMXCTestObserver, TestBundleEventRecord, TestCaseEventRecord, TestSuiteEventRecord, TestEvent (+3 more)

### Community 1 - "Community 1"
Cohesion: 0.18
Nodes (17): CleanItem, FolderUsage, SafetyGrade, careful, review, safe, SmartScanner, StorageScan (+9 more)

### Community 2 - "Community 2"
Cohesion: 0.13
Nodes (17): SafetyVault, VaultItem, VaultSession, makeTempDir(), SafetyVaultTests, setModified(), SmartScannerTests, writeFile() (+9 more)

### Community 3 - "Community 3"
Cohesion: 0.07
Nodes (18): PulseEngine, AlertsEngineTests, ByteFormatTests, EngineTests, makeSnapshot(), SMCDecodeTests, SMCSensorsLiveTests, SnapshotTests (+10 more)

### Community 4 - "Community 4"
Cohesion: 0.15
Nodes (14): CChar, io_connect_t, String, SensorReadings, SMCDecode, SMCSensors, PulseSMCKeyData, PulseSMCKeyInfo (+6 more)

### Community 5 - "Community 5"
Cohesion: 0.14
Nodes (24): Comparable, Int, MemoryPressure, critical, normal, warning, ProcessSample, SleepAssertion (+16 more)

### Community 6 - "Community 6"
Cohesion: 0.43
Nodes (4): LinearGradient, Double, ProcessSample, TopProcessesPanel

### Community 7 - "Community 7"
Cohesion: 0.17
Nodes (11): ScanState, done, idle, scanning, StorageModel, CleanItem, Set, String (+3 more)

### Community 8 - "Community 8"
Cohesion: 0.19
Nodes (9): Entry, MinuteHistoryStore, MinuteHistoryTests, Date, Double, Int, String, URL (+1 more)

### Community 9 - "Community 9"
Cohesion: 0.15
Nodes (11): CleanSchedule, NSBackgroundActivityScheduler, CleanModel, Bool, CleanItem, CleanRecord, Set, String (+3 more)

### Community 10 - "Community 10"
Cohesion: 0.08
Nodes (23): Calendar, CleanRecord, CleanSchedule, CleanScheduler, Frequency, daily, monthly, weekly (+15 more)

### Community 11 - "Community 11"
Cohesion: 0.20
Nodes (11): Bool, CleanItem, Date, String, VaultSession, CleanFooter, CleanRow, SmartCleanPanel (+3 more)

### Community 12 - "Community 12"
Cohesion: 0.09
Nodes (22): CaseIterable, Identifiable, MonitorEngine, NetworkSample, ProcessExtendedSample, ProcessNode, SortKey, cpu (+14 more)

### Community 13 - "Community 13"
Cohesion: 0.27
Nodes (5): URL, CInt, HANDLE, FileLock, T

### Community 14 - "Community 14"
Cohesion: 0.09
Nodes (20): Color, Double, String, CGPoint, CGSize, Color, Double, Path (+12 more)

### Community 15 - "Community 15"
Cohesion: 0.13
Nodes (13): ProcessNode, MonitorModel, Bool, Double, Duration, Int32, MonitorEngine, NetworkSample (+5 more)

### Community 16 - "Community 16"
Cohesion: 0.29
Nodes (5): Color, Halo, Color, Double, UInt32

### Community 17 - "Community 17"
Cohesion: 0.32
Nodes (5): SleepAssertionReader, Int32, Set, SleepAssertion, String

### Community 18 - "Community 18"
Cohesion: 0.25
Nodes (7): CGRect, FolderUsage, SafetyGrade, Color, Double, gradeColor(), TreemapView

### Community 19 - "Community 19"
Cohesion: 0.29
Nodes (5): ProcessSampler, Int, pid_t, ProcessSample, UInt64

### Community 20 - "Community 20"
Cohesion: 0.29
Nodes (6): Develop, Layout, Performance budget, Pulse for Mac, Requirements, Ship a local .app

### Community 21 - "Community 21"
Cohesion: 0.29
Nodes (6): Color, Int32, PulseAlert, String, AlertCard, AlertsSection

### Community 22 - "Community 22"
Cohesion: 0.40
Nodes (3): MemorySampler, MemoryPressure, UInt64

### Community 23 - "Community 23"
Cohesion: 0.53
Nodes (3): SystemInfo, Int, String

### Community 24 - "Community 24"
Cohesion: 0.20
Nodes (11): Bool, Color, SidebarItem, clean, dashboard, devMode, health, monitor (+3 more)

### Community 25 - "Community 25"
Cohesion: 0.40
Nodes (3): App, PulseApp, Scene

### Community 26 - "Community 26"
Cohesion: 0.40
Nodes (3): ByteFormat, String, UInt64

### Community 27 - "Community 27"
Cohesion: 0.40
Nodes (3): Double, String, MenuBarContent

### Community 29 - "Community 29"
Cohesion: 0.34
Nodes (17): String, UInt64, Codable, CustomStringConvertible, TestAttachment, TestCaseFailureRecord, TestErrorInfo, TestLocation (+9 more)

### Community 31 - "Community 31"
Cohesion: 0.12
Nodes (17): DisplayRow, Bool, Color, Int, Int32, MonitorEngine, NetworkSample, ProcessExtendedSample (+9 more)

### Community 32 - "Community 32"
Cohesion: 0.20
Nodes (9): Binding, Bool, CleanRecord, Color, Date, String, AutoCleanCard, CleanHistoryCard (+1 more)

### Community 35 - "Community 35"
Cohesion: 0.14
Nodes (13): DashboardModel, BatteryHistoryStore, Double, Duration, Int, Int32, Never, PulseAlert (+5 more)

### Community 36 - "Community 36"
Cohesion: 0.40
Nodes (3): NetworkSampler, TimeInterval, UInt64

### Community 37 - "Community 37"
Cohesion: 0.50
Nodes (3): Color, Double, CoreHeatmap

### Community 38 - "Community 38"
Cohesion: 0.19
Nodes (8): DiskHistoryStore, Entry, DiskHistoryTests, Date, Int64, TimeInterval, UInt64, URL

### Community 39 - "Community 39"
Cohesion: 0.12
Nodes (19): Action, quitProcess, showDetails, AlertsEngine, PulseAlert, Severity, critical, info (+11 more)

### Community 40 - "Community 40"
Cohesion: 0.10
Nodes (27): Equatable, Error, BatteryDecode, BatteryHealth, HealthSampler, Kind, globalAgent, userAgent (+19 more)

### Community 41 - "Community 41"
Cohesion: 0.15
Nodes (12): Data, Benchmark, BenchmarkResult, BenchmarkStore, Config, Duration, BenchmarkTests, Date (+4 more)

### Community 42 - "Community 42"
Cohesion: 0.15
Nodes (10): HealthModel, BatteryHealth, BenchmarkResult, Bool, Duration, Never, StartupItem, String (+2 more)

### Community 43 - "Community 43"
Cohesion: 0.17
Nodes (6): BatteryDecodeTests, BatteryHistoryStoreTests, Any, Bool, Int, String

### Community 44 - "Community 44"
Cohesion: 0.30
Nodes (9): backfillBatteryHistoryFromSystemLog(), BatteryHistoryStore, Entry, parseLogContent(), splitBatterySession(), Date, String, TimeInterval (+1 more)

### Community 45 - "Community 45"
Cohesion: 0.24
Nodes (7): BatteryHealth, BenchmarkResult, Color, Int, String, BatteryCard, BenchmarkCard

### Community 46 - "Community 46"
Cohesion: 0.12
Nodes (16): SidebarItem, View, CleanItem, BatteryHistoryStore, Date, StartupItem, Void, Timer (+8 more)

### Community 47 - "Community 47"
Cohesion: 0.12
Nodes (6): Swift, XCTAttachment, XCTSourceCodeContext, XCTSourceCodeFrame, XCTSourceCodeLocation, XCTSourceCodeSymbolInfo

### Community 48 - "Community 48"
Cohesion: 0.26
Nodes (7): DevModeSampler, ProcessFDSample, SysctlProperty, Int, Int32, Int64, String

### Community 49 - "Community 49"
Cohesion: 0.25
Nodes (8): assertionFailure, performanceRegression, system, thrownError, uncaughtException, unknown, unmatchedExpectedFailure, TestIssueType

### Community 50 - "Community 50"
Cohesion: 0.52
Nodes (6): TestEventRecord, TestBundleEventRecord, TestCaseEventRecord, TestCaseFailureRecord, TestSuiteEventRecord, TestSuiteFailureRecord

### Community 51 - "Community 51"
Cohesion: 0.40
Nodes (3): Int, XCTExpectedFailure, XCTIssue

### Community 52 - "Community 52"
Cohesion: 0.33
Nodes (4): ProcessFDSample, DevModeModel, String, SysctlProperty

### Community 53 - "Community 53"
Cohesion: 0.50
Nodes (4): Bool, TestFailureKind, expected, unexpected

### Community 55 - "Community 55"
Cohesion: 0.67
Nodes (3): TestEvent, finish, start

## Knowledge Gaps
- **179 isolated node(s):** `Encodable`, `HANDLE`, `CInt`, `T`, `start` (+174 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `View` connect `Community 46` to `Community 32`, `Community 37`, `Community 6`, `Community 40`, `Community 11`, `Community 45`, `Community 14`, `Community 18`, `Community 21`, `Community 24`, `Community 25`, `Community 27`, `Community 31`?**
  _High betweenness centrality (0.245) - this node is a cross-community bridge._
- **Why does `VitalCard` connect `Community 40` to `Community 46`?**
  _High betweenness centrality (0.105) - this node is a cross-community bridge._
- **Why does `SidebarView` connect `Community 24` to `Community 1`, `Community 46`?**
  _High betweenness centrality (0.080) - this node is a cross-community bridge._
- **Are the 8 inferred relationships involving `SmartScanner` (e.g. with `.runScan()` and `.preview()`) actually correct?**
  _`SmartScanner` has 8 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Encodable`, `HANDLE`, `CInt` to the rest of the system?**
  _179 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.12550607287449392 - nodes in this community are weakly interconnected._
- **Should `Community 3` be split into smaller, more focused modules?**
  _Cohesion score 0.06747638326585695 - nodes in this community are weakly interconnected._