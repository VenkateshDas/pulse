# Evidence-driven remedies

Choose the smallest action that addresses the observed condition. Preview consequential actions, retain exact application/file identity, respect prior explicit authorization, and report partial failures. A diagnosis request alone does not authorize app closure or deletion.

- Memory pressure with a known unused app: inspect its main PID, preview graceful `quit`, then act only when authorized. Save prompts may need user input. Never force quit helpers or system services.
- Browser-specific work: identify the tab/extension through its Task Manager; suggest pausing media or saving and closing a confirmed unused tab. Restart only after saving work and user authorization. Do not claim that all tabs will restore.
- Temporary updater/indexer: re-observe after it settles; avoid disrupting an update or disabling indexing merely because it consumes resources.
- Storage shortage: catalog scan, exact target preview, then authorized Trash move. Moved bytes remain allocated until Trash is emptied. Duplicate groups and snapshots are evidence, not automatic deletion targets.
- Heat/battery: address sustained workload and inspect assertions/settings. Do not present charging health or CPU shares as exact energy savings.
- Network issue: use configuration and destination timing evidence. Do not flush routes, radios, DNS or reset permissions as blanket optimization.
- Startup helpers: inspect configuration and ownership. Use the app's existing reversible user-agent control when explicitly authorized; the diagnostic CLI inventory remains read-only. Disabling a plist takes effect at next login and does not prove the running job stopped.

After an action, report its actual completion status, remaining work and recovery method where applicable. Run the same observation under comparable conditions and state whether pressure, active swapping, persistent CPU or responsiveness changed. If the symptom is unresolved, retain the evidence and narrow the next check rather than stacking unrelated maintenance.
