# Graph Report - pulse  (2026-06-13)

## Corpus Check
- 74 files · ~43,148 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1048 nodes · 2067 edges · 59 communities (55 shown, 4 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 59 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `6fb8e902`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

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
- [[_COMMUNITY_Community 56|Community 56]]

## God Nodes (most connected - your core abstractions)
1. `View` - 52 edges
2. `StorageModel` - 42 edges
3. `CleanModel` - 29 edges
4. `SmartScanner` - 29 edges
5. `DashboardModel` - 28 edges
6. `MonitorModel` - 22 edges
7. `CleanScheduler` - 22 edges
8. `SafetyVault` - 22 edges
9. `HealthModel` - 19 edges
10. `makeSnapshot()` - 18 edges

## Surprising Connections (you probably didn't know these)
- `AlertCard` --references--> `View`  [EXTRACTED]
  Sources/Pulse/Views/AlertsSection.swift → Sources/Pulse/PulseApp.swift
- `AlertsSection` --references--> `View`  [EXTRACTED]
  Sources/Pulse/Views/AlertsSection.swift → Sources/Pulse/PulseApp.swift
- `AutoCleanCard` --references--> `View`  [EXTRACTED]
  Sources/Pulse/Views/CleanView.swift → Sources/Pulse/PulseApp.swift
- `CleanHistoryCard` --references--> `View`  [EXTRACTED]
  Sources/Pulse/Views/CleanView.swift → Sources/Pulse/PulseApp.swift
- `CleanPreviewCard` --references--> `View`  [EXTRACTED]
  Sources/Pulse/Views/CleanView.swift → Sources/Pulse/PulseApp.swift

## Import Cycles
- None detected.

## Communities (59 total, 4 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.13
Nodes (18): AsyncStream, StorageNode, StorageScanner, Bool, CleanRecord, Color, Int, String (+10 more)

### Community 1 - "Community 1"
Cohesion: 0.15
Nodes (25): Equatable, CleanItem, FolderUsage, SafetyGrade, careful, review, safe, SmartScanner (+17 more)

### Community 2 - "Community 2"
Cohesion: 0.12
Nodes (17): SafetyVault, VaultItem, VaultSession, makeTempDir(), SafetyVaultTests, setModified(), SmartScannerTests, writeFile() (+9 more)

### Community 3 - "Community 3"
Cohesion: 0.05
Nodes (27): Entry, MinuteHistoryStore, PulseEngine, AlertsEngineTests, ByteFormatTests, EngineTests, makeSnapshot(), MinuteHistoryTests (+19 more)

### Community 4 - "Community 4"
Cohesion: 0.15
Nodes (14): io_connect_t, String, SensorReadings, SMCDecode, SMCSensors, PulseSMCKeyData, PulseSMCKeyInfo, CChar (+6 more)

### Community 5 - "Community 5"
Cohesion: 0.14
Nodes (24): Comparable, Int, MemoryPressure, critical, normal, warning, ProcessSample, SleepAssertion (+16 more)

### Community 6 - "Community 6"
Cohesion: 0.43
Nodes (4): LinearGradient, Double, ProcessSample, TopProcessesPanel

### Community 7 - "Community 7"
Cohesion: 0.09
Nodes (20): Hashable, Hasher, FlatVaultItem, ScanState, done, idle, scanning, StorageModel (+12 more)

### Community 8 - "Community 8"
Cohesion: 0.18
Nodes (11): CleanItem, Color, SafetyGrade, String, Color, SafetyGrade, String, SmartCleanCard (+3 more)

### Community 9 - "Community 9"
Cohesion: 0.14
Nodes (11): NSBackgroundActivityScheduler, CleanModel, Bool, CleanItem, CleanRecord, CleanSchedule, Set, String (+3 more)

### Community 10 - "Community 10"
Cohesion: 0.06
Nodes (38): Calendar, CaseIterable, Codable, CodingKey, Decoder, CleanRecord, CleanSchedule, CleanScheduler (+30 more)

### Community 11 - "Community 11"
Cohesion: 0.17
Nodes (11): Color, Int, SafetyGrade, StorageNode, String, TreemapCell, Void, StorageLens (+3 more)

### Community 12 - "Community 12"
Cohesion: 0.10
Nodes (21): Identifiable, MonitorEngine, NetworkSample, ProcessExtendedSample, ProcessNode, SortKey, cpu, memory (+13 more)

### Community 13 - "Community 13"
Cohesion: 0.26
Nodes (8): TimelineSnapshot, TimelineStore, Date, Int64, String, TimeInterval, UInt64, URL

### Community 14 - "Community 14"
Cohesion: 0.13
Nodes (13): CGPoint, CGSize, Color, Double, Path, CGPoint, CGSize, Double (+5 more)

### Community 15 - "Community 15"
Cohesion: 0.14
Nodes (13): ProcessNode, MonitorModel, Bool, Double, Duration, Int32, MonitorEngine, NetworkSample (+5 more)

### Community 16 - "Community 16"
Cohesion: 0.29
Nodes (5): Color, Halo, Color, Double, UInt32

### Community 17 - "Community 17"
Cohesion: 0.32
Nodes (5): SleepAssertionReader, Int32, Set, SleepAssertion, String

### Community 18 - "Community 18"
Cohesion: 0.18
Nodes (13): CGRect, Color, Double, Int, SafetyGrade, StorageNode, Void, StorageLens (+5 more)

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
Cohesion: 0.18
Nodes (12): Bool, Color, SidebarItem, clean, dashboard, diagnostics, health, monitor (+4 more)

### Community 25 - "Community 25"
Cohesion: 0.22
Nodes (5): App, MenuBarMetric, PulseApp, Scene, String

### Community 26 - "Community 26"
Cohesion: 0.40
Nodes (3): ByteFormat, String, UInt64

### Community 27 - "Community 27"
Cohesion: 0.36
Nodes (4): Double, String, SystemSnapshot, MenuBarContent

### Community 29 - "Community 29"
Cohesion: 0.22
Nodes (6): TimelineModel, Date, Int64, StorageScan, UInt64, TimelineSnapshot

### Community 31 - "Community 31"
Cohesion: 0.09
Nodes (25): DisplayRow, View, Bool, Color, Int, Int32, MonitorEngine, NetworkSample (+17 more)

### Community 32 - "Community 32"
Cohesion: 0.14
Nodes (12): Binding, Bool, CleanItem, CleanRecord, CleanSchedule, Color, Date, String (+4 more)

### Community 35 - "Community 35"
Cohesion: 0.08
Nodes (21): DashboardModel, MenuBarMetric, battery, cpu, diskFree, memory, temperature, BatteryHistoryStore (+13 more)

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
Cohesion: 0.07
Nodes (27): AnyView, Content, Action, quitProcess, showDetails, AlertsEngine, PulseAlert, Severity (+19 more)

### Community 40 - "Community 40"
Cohesion: 0.12
Nodes (19): Error, BatteryDecode, BatteryHealth, HealthSampler, Kind, globalAgent, userAgent, StartupItem (+11 more)

### Community 41 - "Community 41"
Cohesion: 0.15
Nodes (11): Benchmark, BenchmarkResult, BenchmarkStore, Config, Duration, BenchmarkTests, Date, Double (+3 more)

### Community 42 - "Community 42"
Cohesion: 0.16
Nodes (10): HealthModel, BatteryHealth, BenchmarkResult, Bool, Duration, Never, StartupItem, String (+2 more)

### Community 43 - "Community 43"
Cohesion: 0.17
Nodes (6): BatteryDecodeTests, BatteryHistoryStoreTests, Any, Bool, Int, String

### Community 44 - "Community 44"
Cohesion: 0.26
Nodes (11): backfillBatteryHistoryFromSystemLog(), BatteryHistoryStore, Entry, parseLogContent(), splitBatterySession(), Date, Int, String (+3 more)

### Community 45 - "Community 45"
Cohesion: 0.24
Nodes (7): BatteryHealth, BenchmarkResult, Color, Int, String, BatteryCard, BenchmarkCard

### Community 46 - "Community 46"
Cohesion: 0.13
Nodes (17): BatteryHistoryStore, Date, StartupItem, Void, String, VaultSession, StorageModel, View (+9 more)

### Community 47 - "Community 47"
Cohesion: 0.31
Nodes (6): Bool, SidebarItem, String, Void, Command, CommandPaletteView

### Community 48 - "Community 48"
Cohesion: 0.26
Nodes (7): DevModeSampler, ProcessFDSample, SysctlProperty, Int, Int32, Int64, String

### Community 49 - "Community 49"
Cohesion: 0.38
Nodes (4): Color, Double, String, DashboardView

### Community 50 - "Community 50"
Cohesion: 0.33
Nodes (5): StorageNode, String, TreemapCell, Void, StorageDetailPanel

### Community 51 - "Community 51"
Cohesion: 0.38
Nodes (4): Date, Int64, String, TimelineView

### Community 52 - "Community 52"
Cohesion: 0.33
Nodes (4): ProcessFDSample, DevModeModel, String, SysctlProperty

### Community 54 - "Community 54"
Cohesion: 0.50
Nodes (3): parsePMSetLog(), Date, TimeInterval

### Community 55 - "Community 55"
Cohesion: 0.67
Nodes (3): purgeableBytes(), rawFreeBytes(), UInt64

## Knowledge Gaps
- **218 isolated node(s):** `CleanItem`, `VaultSession`, `Set`, `UInt64`, `cpu` (+213 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `View` connect `Community 31` to `Community 32`, `Community 1`, `Community 37`, `Community 6`, `Community 11`, `Community 45`, `Community 46`, `Community 14`, `Community 49`, `Community 21`, `Community 24`, `Community 25`, `Community 27`?**
  _High betweenness centrality (0.070) - this node is a cross-community bridge._
- **Why does `Action` connect `Community 39` to `Community 1`?**
  _High betweenness centrality (0.057) - this node is a cross-community bridge._
- **What connects `CleanItem`, `VaultSession`, `Set` to the rest of the system?**
  _218 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.12873563218390804 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.12311265969802555 - nodes in this community are weakly interconnected._
- **Should `Community 3` be split into smaller, more focused modules?**
  _Cohesion score 0.05245901639344262 - nodes in this community are weakly interconnected._
- **Should `Community 5` be split into smaller, more focused modules?**
  _Cohesion score 0.14039408866995073 - nodes in this community are weakly interconnected._