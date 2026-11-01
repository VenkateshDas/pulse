# First guide — research, claims and release record

Owner-approved scope: general Mac users; find what is using storage before choosing any cleanup. English, global audience, free tools. Intended URL: https://venkateshdas.github.io/pulse/guides/whats-taking-up-space-on-mac/. Implementation branch: feat/mac-storage-guide. This report does not imply publication or search ranking.

## Keyword decision

Research reviewed 31 October 2026. Queries: “what's taking up space on my Mac”, “how to find large files on Mac”, “Mac storage full but can't find files”, “what is System Data on Mac”. Search results demonstrate relevant informational intent and numerous cleanup-product articles; this is qualitative discovery, not measured search volume, difficulty or proof of an easy ranking. No keyword suite purchased. Search Console query data was still processing at the preceding baseline review.

Primary question: what's taking up space on my Mac? Supporting questions: how to find large files; why a file search misses storage; what System Data means. One page answers this coherent investigation; no near-duplicate keyword pages. Differentiation is the observed file-versus-folder example and a useful built-in workflow before the product invitation. Xcode and Docker topics are deferred following the owner's general-Mac choice.

Primary research links: [Apple storage overview](https://support.apple.com/en-in/102624), [categories](https://support.apple.com/kk-kz/guide/mac-help/syspf5a64aa6/mac), [Finder criteria](https://support.apple.com/en-nz/guide/mac-help/-mh15155/mac), [search limitations](https://support.apple.com/en-by/guide/mac-help/mchlp2962/mac), [Get Info](https://support.apple.com/en-am/guide/mac-help/mchlp1774/mac), [local snapshots](https://support.apple.com/en-gb/102154), [iCloud downloads](https://support.apple.com/en-gb/guide/mac-help/-mchl1a02d711/mac), [synced deletion](https://support.apple.com/en-sg/109344), [Trash](https://support.apple.com/en-al/guide/mac-help/mchlp1093/mac). Some direct Apple fetches returned HTTP 429; indexed official page text and the local walkthrough provided the evidence. No third-party cleanup article supplies technical instructions. Version-neutral Apple pages may advance to a newer OS; visible steps are separately checked below.

## Claim/source/check matrix

| Published advice | Evidence | Boundary |
|---|---|---|
| General → Storage, available space and inspectable categories | Apple storage overview; directly opened System Settings General → Storage | Real personal totals were read for verification only, never included in the page/assets |
| Documents offers Large Files, Downloads and File Browser | Apple categories; actual Documents sheet and File Browser opened | No Delete action; labels vary by version/language |
| Command-F, scope, Other → File Size, greater-than and units | Apple Finder criteria; selected folder scope, attribute picker and size comparison in Finder | Local sample used 5 MB; 1 GB / 100 MB are editorial starting thresholds, not measured recommendations |
| Size search misses a folder's aggregate | Created eight 1 MiB sample files in Sample exports and separate 3/12 MiB files; >5 MB search returned the 12 MiB sample only | The demo is deliberately tiny; sizes are not claims about customer cleanup |
| Get Info reports the folder total | Actual Command-I on Sample exports showed 8,388,608 bytes / 8.4 MB on disk | No systemwide folder enumeration, measurement guarantee or deletion |
| Search can omit data | Apple's search-limitations page; size search demonstrated only selected scope | No claim Finder sees every file or reconciles the whole disk |
| System Data is a classification, not one removal target | Apple's category definition | No universal safe-to-delete number or cache purge instructions |
| Available and free space differ | Apple category definitions | No sum of category/search/folder totals presented as exact accounting |
| Local snapshots are automatically managed and count as available | Apple's local snapshot article | Source-backed explanation; no snapshot deletion or Time Machine settings changed |
| iCloud deletion can affect other synced devices | Apple Desktop/Documents iCloud article; downloads guide | Source-backed; no cloud files manipulated. No cloud copy/backup promise |
| Trash is distinct from permanent removal | Apple Trash guide; Storage Documents explicitly says permanent erase | No personal file removed, no Trash emptying, no cleanup performance claim |
| Pulse folder explorer | Existing fictional storage SVG and live landing claims | In development, early access only; not a download or a live reading |

## Visual and editorial contract

Read surface, approved established Pulse green/system typography. One route diagram, real Finder search screenshot with HTML markers, an eight-files-to-folder-total diagram, real Get Info screenshot, and labeled fictional Pulse preview. Sources sit beside the relevant explanation and in a numbered source list. No generated image was necessary: factual native UI and exact diagrams explain the task more reliably. Raster provenance sidecars accompany the two screenshots. No personal filenames, identity, disk totals or subscriber data are published. Screenshots show the system locale's comma decimal separator; prose uses English decimal punctuation.

The disposable practice directory is /Users/Shared/Pulse Storage Example (23 MiB of authored sample data). Temporary original captures are /tmp/pulse-guide-captures. Neither directory is a public build asset or source of future telemetry. The real Storage screen was not saved into the repository.

## Implementation / measurement

Static article and homepage entry/footer link; no framework, third-party font, new analytics vendor or article animation dependency. Sitemap lists only homepage and the new canonical guide; thanks stays noindex. Article JSON-LD uses the visible Pulse organization byline and review date; no fictional publication date, person or expertise credential is invented.

Capture explicitly permits only canonical homepage/guide routes. Local root aliases normalize to the same paths and remain test traffic; public root/unknown paths fail closed. `guide_product_click` sends only the fixed guide identifier plus existing coarse context. Existing early-access clicks and form-handoff attempts keep their meanings. No confirmed-signup inference or identity joins. Page breakdowns supplement native saved charts; subscription stock remains in MailerLite.

## Release checks

- Automated checks: `node landing/scripts/check-analytics.cjs`, `python3 landing/scripts/check-pages.py`, JS syntax and `git diff --check`.
- Browser QA: record results below after checking real 320/390/1440 widths, no overflow, image loading, fragment destinations, keyboard navigation, consent withdrawal and hosted form destination. No test signup/email is authorized by this guide task.
- Required CI: Build & Test (macOS). No native source changes; CI uses make for the native build/test gate.
- Stop before merge for owner visual/functional approval under the owner-approved implementation plan. This does not authorize PR #97's merge.
- After approved merge: verify Pages, HTTP 200/canonical/assets/sitemap and public test-flagged events; only then inspect the new public URL in Search Console. The already scheduled sitemap monitor remains responsible for the existing processing discrepancy.
- Weekly review: include this guide in page/query observations; no rankings promised and no cross-provider conversion rate. Publishing/approval remains manual.

## Design completion

Checked the finished article and shared stylesheet against PRODUCT.md, DESIGN.md and the approved Read-surface contract in `.impeccable/surfaces/storage-guide.md`; inspected the saved 1440px, 390px and 320px review captures. The built-in Storage/Finder answer precedes the Pulse invitation. Native sample screenshots, the folder-total diagram, adjacent citations and the explicitly fictional product preview support the investigation without exposing personal files. The existing Pulse green, system typography, opaque surfaces, restrained corners and readable row/divider structure carry through; the article’s reading width, contents rail and mobile stacking are surface-specific adaptations.

The finish reviewer returned **ship**, with no material fixes; three detector warnings about 22px row padding were reviewed as false positives. Retained the incumbent product and design system unchanged: no PRODUCT.md or DESIGN.md edits, no durable token/component changes, and no UI edits during documentation. `.impeccable/design.json` was already absent and remains absent; DESIGN.md’s existing noncanonical headings were not migrated. The indexed `docs/product_spec.html` was also absent, including at its linked original-checkout path; this existing documentation gap was not repaired. This completion record covers design evidence, not publication or owner merge approval.


## Final QA — 1 November 2026

Measured real browser viewports: 1440×1000, 390×844 and 320×844. No document overflow; all checked content boxes stayed within the 320px viewport. All three guide images were loaded before final full-page captures. TOC links reach the intended sections; keyboard skip focuses main. Analytics opt-in, guide-product link and opt-out worked; the new event was visibly received in PostHog with the canonical guide page and `is_test=true`. No email, file path or query data was captured; no signup was submitted. Native Node privacy/route tests and static page/asset/fragment/sitemap/schema checks pass.

Updated existing PostHog insight IDs 6990613 / 6990614 / 6990615 with page breakdowns, retaining daily browser math and `is_test=false`. Dashboard's seven-day default is preserved; referral-source and CTA-position charts are unchanged. The weekly review automation now includes this guide conditionally after public deployment. No new campaign, API credential or recurring email subscription was created. Review-date text and matching Article metadata were set to 1 November during final QA; the original research occurred 31 October.
