# Pulse landing page: current feature coverage

Scope: downloadable v0.3.0-beta.5 / main, not unmerged harness work. Keep the existing layout, visual styling, interactions and beta download URL. Primary action remains Download beta; waitlist is optional.

## Recommended structure

Replace the fixed “9 apps” count with “Your Mac, understood.” Keep the existing headline “Your whole Mac, in one window.”

Subheading: “Find what is using your Mac, review what is taking up space, and choose what to do next. Monitor performance, remove apps and leftovers, manage your displays, or ask Pulse for help.”

Use the existing feature grid for these source-backed groups; give advanced tools a compact section below it rather than forcing everything into the hero.

| Feature | Copy and limits | Implementation evidence |
|---|---|---|
| Home and performance | CPU, memory, disk, temperature, GPU where available; plain-language condition summaries and app attribution. | DashboardModel; DiagnosisEngine; sensors |
| Files and storage map | Browse sized folders and inspect storage; label illustrative website graphics as examples. | StorageView; StorageModel |
| Reviewed cleanup | Review caches, logs, developer/AI-tool data and hidden space before selected Trash moves. No promised speed boost. | CleanView; CleanCatalog; InsightScanner |
| Exact duplicates | Find matching file contents and review copies before removal. No perceptual photo-matching claim. | DuplicateView; DuplicateScanner |
| Storage changes | Compare recorded observations to identify growth; history depends on scans. | GrowthView; TimelineStore |
| Trash and recovery | Inspect Trash and recorded moves. Restoration requires the item still to exist; emptying Trash cannot be undone. | TrashView; UndoJournal |
| Apps and leftovers | Review installed apps, confidence-graded related files and orphan helpers before uninstalling. No guarantee of finding every leftover. | UninstallView; UninstallScanner; BundleGuard |
| Battery and energy | Charge, capacity, cycles, session history, capacity trend, Bluetooth battery where available; app energy shares are CPU-based estimates. | HealthView; BatterySessionStore |
| Internet | Connection/Wi-Fi readings, throughput, bounded manual HTTPS speed estimates, opt-in automatic tests and test history. | NetworkView; NetworkModel; SpeedTestRunner |
| Displays | Named display sliders, supported hardware brightness, adaptive matching and software dimming; physical keys follow display selection/cursor behavior. Hardware support varies. | DisplaysView; BrightnessEngine; MediaKeyManager |
| Menu bar | Hide/reveal icons with chevron and auto-hide; selectable CPU, memory, temperature and battery readings; popover controls. | MenuBarManager; MenuBarStat; PopoverView |
| Keep awake | User-controlled system/display sleep prevention with duration and hotkey controls. | Sleep prevention controls |
| Activity and alerts | Recorded activity, anomalies and threshold notifications; missing observation periods stay gaps. | TimelineView; ProcessWatcher; AlertEngine |
| Ask Pulse | Optional conversational help with selected provider/model and API key. Questions and requested diagnostic results go to that provider; charges may apply. Review consequential actions. | AgentView; AgentModel; AgentConfiguration |
| App activity and investigations | App groups, process details/history, normal Send Quit for eligible apps and slowdown investigations. | MonitorView; InvestigationView; AppQuit |
| Startup helpers | Review supported launch helpers, manage eligible user helpers; changes affect next sign-in, not all login items. | HealthView startup scope; StartupManager |
| Maintenance | Review supported native maintenance tasks; unavailable operations remain unavailable. Remove DNS/Spotlight/purge “done” demos. | OptimizeModel; OptimizeEngine |
| Performance test and diagnostics | Explicit temporary CPU/memory/storage tests and native diagnostic evidence. Scores are synthetic comparisons. | BenchmarkView; DiagnosticsView |
| Command palette and CLI | Keyboard navigation/quick actions; native CLI and portable agent skill for technical workflows. | CommandPalette; PulseCLI; docs/pulse-cli.md |
| Accessibility and preferences | Light/dark themes, Larger text, keyboard navigation, launch-at-login and update checks. Avoid advertising removed Simple/Pro navigation modes. | SettingsView; SidebarView; Updater |

## Corrections throughout page

- Title, description, social metadata and structured data must reflect current beta and optional Ask Pulse.
- Remove scheduled auto-cleanup, future Pro/Family entitlements, five-Mac licenses, priority support and unverified lifetime pricing promises. Describe the downloadable beta as free, with currently implemented features available; provider costs are separate.
- Replace “never phones home / all data stays local” with local monitoring plus explicit exceptions for AI providers, network tests and update checks.
- Replace universal safety and recovery guarantees with review, protected-path checks, Trash and actual restore limits.
- Remove “near-zero resources” guarantees and the claim that every app surface is purely native; monitoring is native, optional AI has additional runtime/network work.
- Replace guaranteed external-display support and competitor-replacement claims with supported-monitor behavior.
- Update mock app navigation and example labels to current task names; remove fabricated maintenance success and one-click freed-space outcomes. State that moving items to Trash does not immediately free storage.
- FAQ covers AI setup/privacy, storage/restore limits, monitor compatibility, history availability, beta installation and actual pricing.

## Alternatives

1. Recommended: retain design and expand source-backed feature coverage. Lowest risk; complete current feature story.
2. Only add missing cards. Smaller edit but leaves misleading claims elsewhere.
3. Full visual redesign and new screenshots. Larger scope; unnecessary for this content correction.

## Validation

Compare every capability to released source, check headings/links/HTML, inspect desktop and narrow layouts, preserve download behavior, and open a PR with required CI. Publish only after user approval of the revised page.
