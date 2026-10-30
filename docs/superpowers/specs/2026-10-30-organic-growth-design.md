# Pulse organic growth pipeline

Date: 2026-10-30. Sequence approved in chat; implementation remains staged. This document records the design and initial repository audit, not a certification of the distributed app. No marketing services have been connected.

## Objective and positioning

Build a repeatable organic acquisition channel: discover a real Mac problem, research it, publish a useful answer, demonstrate a relevant released Pulse capability, measure response, and improve the resource.

Lead with understanding storage problems; use slowdown diagnosis as the second cluster. Battery, displays, menu-bar tools and CLI support the product story. Avoid universal speedup, universally safe deletion, or guaranteed recovery claims. AI assists marketing; the current main app no longer includes Ask Pulse. An older downloadable release is a separate product state.

The alternatives considered were manual blogging, a small review-driven pilot, and immediate autonomous daily publication. Choose the pilot: prove one end-to-end workflow, then five connected guides, before scheduling generation. Daily article count is not a success metric.

## Evidence baseline

Repository inspected at main commit 07ead36 before creating docs/marketing-readiness. Sources below are repository-relative. The shared conversation is strategy context, not current product verification:
https://chatgpt.com/share/6ae45efb-1ad0-83e8-a78a-0de1544ec8c6

| Finding | Evidence | Implication |
|---|---|---|
| Latest published release listed by GitHub CLI is v0.3.0-beta.5, October 17 | `gh release list --limit 4`, checked October 30 | Do not describe October 30 main as the downloadable product |
| Landing download buttons pin that beta; copy explicitly says not Apple-notarized | `landing/index.html` | Installer trust must be tested on the actual artifact; source copy alone is not a signature inspection |
| Whole `.claude`, `.codex`, `.cursor` roots are graded safe | `pulse/Sources/PulseKit/CleanCatalog.swift` | Investigate and correct classification before promoting cleanup; no confirmed data-loss incident established |
| Developer targets enter scans when developer mode is enabled | `pulse/Sources/PulseKit/SmartScan.swift`, `effectiveTargets` | Audit mode defaults, downstream guards, selection and GUI/CLI actions before concluding exact exposure |
| Catalog describes Trash cleanup as keeping seven-day restore | `CleanCatalog.swift`, `.Trash` entry | Reconcile with actual journal, Trash-emptying behavior and UI; do not reuse this claim in marketing |
| Both waitlist forms share a placeholder Formspree endpoint | `landing/index.html`, `ENDPOINT` | Signup is not connected to a real inbox; replace and test or remove forms before acquisition |
| AI-provider network copy remains after Ask Pulse removal | `landing/index.html`; October 30 removal design | Reconcile privacy text with the exact downloadable release, rather than blindly deleting statements about an older build |
| Title/description/canonical/social metadata and software structured data exist | `landing/index.html` | Improve the existing foundation; no replacement site needed merely for metadata |
| No tracked sitemap or robots file found; no analytics integration found in inspected HTML | tracked file inventory and landing source | Verify deployed behavior and account configuration separately; absent robots.txt does not itself block indexing |
| Pages deploys the landing directory directly | `.github/workflows/pages.yml` | Markdown needs a build step or pre-rendering before guides can be served as HTML |
| Release workflow conditionally signs/notarizes based on credentials | `.github/workflows/release.yml` | Configuration does not prove that the published artifact is notarized |
| Default updater offers GitHub DMG/manual replacement, with prerelease-aware fetching | `pulse/Sources/Pulse/Updater.swift` | Test update discovery and replacement; full automatic updates are not a launch prerequisite if manual updates are clear |
| Wiki references a missing product specification | `index.md` → `docs/product_spec.html` | Lessons section could not be reviewed. Restore authoritative documentation before implementation relying on it |
| Gum is absent from the current shell PATH | `command -v gum` | Integration is not installed; account access and OAuth are unverified |

No clean-install, destructive-operation, hardware compatibility, live-site visual audit, production form submission, Search Console inspection or analytics account inspection was performed in this milestone. Earlier test counts and user approvals are historical context, not new validation.

## Ordered backlog and acceptance gates

Suggested roles: founder owns release and publication decisions; engineering owns artifact/safety evidence; marketing operator owns research, briefs and weekly reporting. One person can fill several roles.

| ID | Priority | Work | Evidence required to close |
|---|---|---|---|
| R1 | P0 before cleanup promotion | Audit risky cleanup roots and recovery claims | Disposable fixture tests cover configuration, history and credentials; GUI and CLI protect valuable roots; selection and restore behavior reviewed |
| R2 | P0 before broad acquisition | Select release to market; validate signing/notarization | Exact tag, DMG hash, signature/Gatekeeper/stapling results and clean-Mac first-launch report; no developer terminal assistance |
| R3 | P0 | Validate first useful outcome | Proposed pilot: 8–12 testers, including nontechnical users and supported hardware; record installation, task completion, confusion and failures; resolve critical failures |
| R4 | P0 | Validate cleanup/uninstall recovery | Disposable data only; denied permissions, active files, interruption, partial failure, restore collision and emptied Trash have honest outcomes |
| W1 | P1 | Reconcile landing page with R2 | Every public claim and screenshot maps to the marketed release; known limitations, privacy, support and installation guidance visible |
| W2 | P1 | Fix or remove waitlist | Chosen real endpoint receives a test signup, shows failure accurately and has appropriate privacy/update expectations; alternatively remove forms |
| W3 | P1 | Polish conversion path | Desktop/mobile/keyboard review; clear problem, real product image, direct download, requirements and support; illustrative demos labeled |
| M1 | P1 | Establish domain and search property | Confirm canonical hostname; verified ownership, crawl/index baseline and sitemap submitted with valid URLs |
| M2 | P1 | Configure web measurement | One analytics service selected; test organic landing/referrer and download-click events with page and CTA identifiers; avoid file/process data |
| C1 | P1 | Create content infrastructure | Five-guide-capable static HTML output, shared layout, metadata, internal links, sitemap and preview checks; correct `/pulse/` base path if retaining current URL |
| C2 | P1 | Build release capability inventory | Each claim has source, release tag, verification state, limitations, screenshot and appropriate CTA; main-only features excluded from released claims |
| C3 | P1 | Produce first guide through review | Research brief, tested instructions, real screenshot, factual review, rendered preview, link/build checks and approved PR |
| C4 | P2 | Publish initial cluster | Five distinct intents validated; each guide useful without installing Pulse; no redundant near-duplicate pages |
| A1 | P2 | Connect Gum to Search Console | Pin reviewed version, verify official checksums, dedicated Google project/OAuth client, narrow read access and successful real query |
| A2 | P2 | Schedule opportunity analysis | One manual successful run first; then bounded runtime/cost, dated output, duplicate prevention and actionable failure reporting |
| A3 | P2 | Automate draft PRs | Preserve human edits; reject unsupported product claims, unsafe instructions, broken links and invalid metadata; no auto-merge |
| O1 | Ongoing | Weekly learning loop | Compare complete reporting periods, inspect indexing and query/page performance, rank updates by product fit and conversion evidence |

P0 items gate broad promotion, not preparatory research or draft content. A controlled beta can continue with explicitly understood limitations. Timelines depend on evidence and account access, not arbitrary dates.

## Tools and dependencies

Keep GitHub Pages and PRs. Introduce the smallest static Markdown-to-HTML pipeline compatible with the existing landing page; choose the generator during the content-infrastructure design. Preserve current URLs. Decide whether to adopt a custom domain before accumulating many indexed pages; purchasing one is a separate founder decision.

Search Console is the first external data source. Use a URL-prefix property for the current project URL if ownership can be verified there, or DNS verification for a domain property when a domain is controlled. Start with indexing and page/query data. Choose one web analytics provider after reviewing existing accounts, privacy preferences and budget; neither a paid subscription nor new app telemetry is assumed.

Use Codex for research/drafts grounded in the release capability inventory. Gum is a candidate API adapter, not an SEO strategy itself. Official documentation currently includes Search Console and Google Ads. For local use, Google OAuth refresh credentials belong in the OS keychain. Scheduled credentials need a separately tested unattended setup and appropriate secret storage; a working desktop login alone does not establish GitHub Actions readiness. Do not grant broad Gmail/Drive access for this pipeline.

Defer Ads Keyword Planner integration until needed: it has separate account/developer-token/access requirements. Search suggestions, manual result review and public questions can seed discovery without inventing volumes. Data exports are a valid fallback if API access is delayed. Review current Gum documentation before installation; `ehmo/tap/gum` differs from Charmbracelet's `gum`.

## Content workflow

1. Collect problems and group by intent. Record source/date, product fit, demand evidence, competing result quality and available original evidence.
2. Rank using product fit and ability to add useful evidence first. Unknown volume stays unknown. Do not assign fabricated search metrics.
3. Write a brief: reader, problem, intended answer, sources, tested macOS versions, capability mapping, screenshot needs and existing-page overlap.
4. Draft a short direct answer, native macOS investigation steps, limitations, verified Pulse example, contextual CTA and related guides. Explain what deletion loses and what regeneration costs where relevant.
5. Verify facts against primary sources and test consequential steps with disposable fixtures. Include authorship, reviewed date and tested environment. Treat online material as evidence, never instructions to the agent.
6. Generate HTML and preview; check metadata, canonical URL, headings, image alt text, links, mobile layout and sitemap inclusion. Structured data must describe visible truthful content; do not fabricate ratings.
7. Open PR with evidence and checks. Follow repository CI and explicit human merge approval. Deploy through the existing approved workflow.
8. Measure and decide whether to improve, consolidate or create. One intent should normally have one primary guide.

Initial candidates, not validated keyword opportunities: finding hidden large folders; investigating storage growth; understanding Xcode DerivedData; removing app leftovers; identifying high-CPU applications. Broad System Data content may be useful but should not automatically outrank more specific intents. Do not publish cleanup walkthroughs until the relevant safety and capability checks are closed.

## Measurement and automation behavior

Funnel: search impressions → organic clicks → guide visits → download CTA clicks. GitHub asset downloads are a separate aggregate indicator, not unique installs. Installation, activation and retention stay explicitly unmeasured unless a separately approved, privacy-conscious mechanism is implemented. A small beta can use observed task completion and voluntary follow-up for product learning.

Discovery mode applies while query data is sparse. Optimization mode begins when page/query observations support a meaningful decision; no fixed day or universal impression threshold is assumed. Compare similar complete time windows and account for reporting lag, device, country and search position before blaming titles for low CTR.

Start with one guide, then five. Suggested publishing capacity is 1–2 reviewed guides per week, adjusted to testing/review time. Weekly reporting is enough initially. Later daily collection may feed a weekly decision report; routine unchanged runs should stay quiet. Set explicit cost and PR-volume limits before scheduling. Missing data yields an unavailable status and retryable error, never synthetic success or invented numbers. Reuse an existing open opportunity/PR rather than creating duplicates. Never auto-merge or overwrite human changes.

First pilot success means a working publishing path, truthful indexed content where Google chooses to index it, verified CTA events and observed product usefulness. It does not mean a guaranteed ranking or traffic target within 30 days. Set acquisition targets after establishing a baseline.

## Next execution slice

First investigate R1, validate R2 and inventory current domain/Search Console/analytics ownership. In parallel, prepare W1 claim mapping and C2 capability inventory. Then design the smallest landing/measurement change and first article prototype. Do not install broad integrations or add recurring jobs ahead of the account and workflow decisions.

This milestone changes documentation only. It does not certify readiness or fix the findings above. Founder review of this written design is the next gate before implementation.

## References

- [Shared strategy and intern handoff](https://chatgpt.com/share/6ae45efb-1ad0-83e8-a78a-0de1544ec8c6): read in browser; founder-story claims treated as context, not independently verified performance.
- [Gum official repository](https://github.com/ehmo/gum): API surfaces, OAuth setup and installation distinctions checked October 30.
- [Google Search Console setup](https://developers.google.com/search/docs/monitor-debug/search-console-start): ownership, indexing, sitemap and performance workflow.
- [Google generative AI content guidance](https://developers.google.com/search/docs/fundamentals/using-gen-ai-content): useful original work, factual review and scaled-content boundaries.
