# Focused Mac investigation

## Slow Mac or browser
Observe while reproducing the complaint. Separate whole-system saturation from a busy single core, memory pressure, active swap traffic, thermal constraints and device activity. Look at leading app groups and then inspect their current PIDs. Brief update/indexing activity can explain a transient episode but is not proof of every slowdown.

For browser helpers, `process PID` classifies renderer, GPU, network, media and extension-renderer arguments when readable. Match PID in the browser's Task Manager. A media service is a clue, not proof of a particular streaming tab. Do not enable debugging ports, scrape browser history, change flags or kill an unidentified helper. Closing a tab can lose work; preserve the user's authorized scope.

## Memory
Pressure is the stronger signal than usage percentage. High used RAM with normal pressure may be healthy caching. Swap occupancy alone does not prove current swapping: use swap-in/out rates. Compression/decompression rates expose churn. RSS excludes compressed/swapped pages and includes shared pages; summed app RSS is not exclusive physical usage. Footprint is a separate native accounting value, not interchangeable with RSS. Growth within a short session is not a proven leak.

## CPU, heat and disk
Process 100% means one fully occupied core and can exceed 100%; system 100% means all cores. Native counters are interval deltas. First readings have no rate baseline. Inspect coverage before naming the top consumer. Protected/other-user task reads can be denied.

Device read/write throughput is activity, not latency, saturation or disk health. Storage layers can overlap. Correlate with process cumulative disk counters, swap rates and user symptoms. Do not penalize SSD throughput using a universal MB/s cutoff. Disk capacity reports important-usage availability (includes purgeable space); it can differ from filesystem free blocks. A cleanup scan can itself create I/O load: run it only for a storage complaint.

## Slow web loading
Read network configuration first; then optionally probe the affected destination. HEAD may be rejected, redirected or handled differently from GET. Report HTTP status and total/DNS/connect/TLS/response timing, preserving absent stages as unknown. Browser authentication, extensions, JavaScript, VPN routing and server behavior can differ from the probe. A tunnel does not establish VPN use. Do not infer internet speed from traffic rates or an old speed test. Refresh/clear network settings only for a demonstrated relevant fault and explicit authorization.

## Battery, sleep and background helpers
Use sensors, history and sleep assertions. Battery app shares estimate CPU-weighted contribution, not measured energy. Startup plists are configuration, not proof a job is running. Missing absolute executable paths warrant review, not automatic removal. Relative programs and modern managed login items may be unresolved. Current idle-sleep assertions do not reconstruct overnight wake reasons.

## Evidence quality
Record the interval and timestamp, severity and confirmed facts, likely contributors, missing evidence and the next discriminating check. A report's contributor is not a causal verdict. Prefer a targeted action and a comparable second observation over generic cleanup.

The native CLI and app must not add shell collectors. If the user explicitly requests external shell investigation, use bounded read-only system tools only when native output cannot resolve the question, explain the added evidence, and account for the probe's own load. Never turn such a fallback into an installed background collector.
