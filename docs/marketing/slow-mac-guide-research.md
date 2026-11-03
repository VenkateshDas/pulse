# Second guide: slow Mac investigation

Research date: 2 November 2026. Status: researched article draft; not published or added to the live Guides index. Article: [Why is my Mac so slow?](articles/why-is-my-mac-so-slow.md).

## Topic and distinct value

The approved organic-growth design names slowdown diagnosis as the second cluster. The first guide already answers storage discovery. This article answers a separate question: how can a general Mac user narrow down a slowdown without indiscriminately terminating processes or cleaning files? It links to the first guide rather than duplicating its instructions.

Searches for Mac slowdown, Activity Monitor CPU and memory-pressure interpretation surfaced informational guides and product-led advice. This is qualitative intent discovery, not evidence of keyword volume, ranking opportunity or reader demand. No Search Console or keyword-volume figures were obtained for this task.

## Evidence and claim boundaries

Primary evidence is Apple's user-facing documentation, appropriate for supported UI behaviour and metric definitions. No peer-reviewed performance experiment or original causal measurement was conducted. Instructions are documentation-verified, not locally demonstrated; no claimed macOS-version testing, personal case study, benchmark result or screenshot is invented. Some Apple pages rate-limited direct fetches; their indexed full text was reviewed through search. Locale/version differences remain a publication check.

| Claim | Primary source | Boundary |
| --- | --- | --- |
| Several possible causes include storage, memory demand and compatibility | [If your Mac runs slowly](https://support.apple.com/en-mide/guide/mac-help/mchlp1731/27/mac/27) | Does not rank causes or establish a universal free-space threshold |
| Sorting, process details, All Processes and hierarchy | [Process information](https://support.apple.com/en-ng/guide/activity-monitor/actmntr1001/mac) | A process ranking is not a fault diagnosis |
| CPU panes and User/System/Idle definitions | [CPU activity](https://support.apple.com/guide/activity-monitor/view-cpu-activity-actmntr43452/mac) | No universal problematic CPU percentage or observation duration |
| Pressure colours and unused-memory interpretation | [Check RAM needs](https://support.apple.com/en-asia/guide/activity-monitor/actmntr34865/10.14/mac/15.0) | Recurring workload pressure deserves investigation; one sample cannot justify buying hardware |
| Cached, compressed and swap definitions | [Memory usage](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac) | Swap amount differs from rate; swap amount alone cannot establish causation (inference) |
| kernel_task thermal role | [kernel_task](https://support.apple.com/en-ie/102172) | One documented role; not an explanation of every instance of high CPU |
| Quit versus Force Quit | [Quit a process](https://support.apple.com/en-ie/guide/activity-monitor/actmntr1002/10.14/mac/15.0) | Immediate termination can lose work or affect dependencies |

The observation → one change → repeat method is editorial troubleshooting advice. It is not presented as an Apple protocol or controlled study. Improvement supplies a lead, not proof. Deliberately omitted: unsupported CPU cutoffs, swap/SSD lifespan claims, memory-cleaner promises, routine cache deletion, reset recipes, automatic process killing and a complete hardware diagnosis.

## Product verification

Reviewed current-main `pulse/Sources/Pulse/Views/DashboardView.swift`: CPU card, memory-pressure colour mapping, memory breakdown and swap formatting support the restrained product paragraph. No Ask Pulse, AI diagnosis, automatic fix, universal speedup, app-wide recording or release availability claim. Early-access destination remains the existing public homepage.

## Writing and editing

Read research-pipeline for research/content structure and humanizer for the final prose edit. The pipeline's external `Templates/Article Template.md` was not found in the checked local vault locations, so this draft uses the existing Pulse guide as its format/voice reference and humanizer as the applicable editing workflow. Its autobiographical curiosity-note rules do not apply to a product help article; no personal observation is fabricated.

Editorial pass removed generic optimisation promises, repetitive headings and a false single-cause narrative. Remaining technical terms are explained at first use. Citations sit beside the relevant claims. Original and revised opening were reviewed internally; the saved article is the revised draft.

## Publication handoff

Owner asked for research and an article. Deliver Markdown and this evidence record now. A subsequent site implementation should reuse the current redesign and check actual UI labels on a named macOS version, mobile/desktop rendering, internal links, canonical metadata/schema, sitemap and the analytics route allowlist. Use disposable/example data for any demonstration. Do not present this draft as tested, deployed, indexed or approved for merge. No website, analytics account, signup flow or native application changes in this task.

## Review revision — 2 November 2026

Reviewed the complete draft against the claim table and existing guide voice. Revised the opening to give the investigation immediately; removed repeated universal-speedup disclaimers and author-process commentary. Added a decision table so readers can act on their observations, moved Quit/Force Quit guidance next to the first quitting step, and added process hierarchy as an investigation tool. Added an explicitly hypothetical before/after note to demonstrate useful evidence without inventing a test result. Changed product availability wording to an early-access waitlist.

The table and hypothetical example are editorial applications of the cited definitions, not measured findings. A resource pattern cannot establish an app defect or a hardware diagnosis. Memory guidance still uses the explicitly versioned Apple source already reviewed; direct re-fetches of three Apple pages returned HTTP 429 during this review. No additional UI-version verification or live test is claimed. Checked article length, source links, local reference targets and diff whitespace; native tests are unnecessary for these documentation-only edits. Publication handoff remains outstanding.

## Website publication — 3 November 2026

Owner requested website publication. Rendered the reviewed article at `/guides/why-is-my-mac-so-slow/`, using the current field-guide layout, adjacent citations, contents navigation, responsive decision table and existing signup configuration. Added a Guides listing, a related link from the storage article, canonical/social metadata, Article/Breadcrumb schema and sitemap entry. The opening route diagram is an editorial checklist, not a measurement or screenshot. Preserved the visible documentation-only verification limit.

Added only the fixed new route and guide identifier to existing per-page analytics, preserving opt-outs, browser signals and unknown-route suppression. Extended route and attribution tests and static schema checking to cover both articles. Local checks pass (six pages, four sitemap URLs); inspected 1440px, 390px and 320px layouts, with no document overflow. The contents anchor and hub-to-article navigation work; no signup was submitted. CI, merge and public deployment are recorded by the subsequent PR/Pages history.

### Design handoff

This is a narrow extension of the existing website's Read-mode guides: retain the warm white and green palette, readable article column, contents navigation, adjacent source links and restrained early-access invitation. The CPU → Memory → Storage diagram is a reading aid, not live telemetry. The Guides hub retains the established listing composition, with separate sections for storage and slowdown; preserve enough space between those sections to keep their headings distinct from the preceding listing. These are surface-specific implementation notes, with no change to the durable product or native-app design system in `PRODUCT.md` or `DESIGN.md`.
