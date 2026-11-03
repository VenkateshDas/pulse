# SEO implementation and publication record — 3 November 2026

## Authorization and scope

The owner approved the [bounded website pass](../superpowers/specs/2026-11-03-search-discovery-design.md) in chat after reviewing its concrete copy, metadata and validation scope. New articles remain drafts for review. The current Pulse redesign, public URLs and early-access positioning are preserved.

## Prepared website changes

- Homepage title, description and social copy name the actual Mac performance/storage category. Visible description retains the product's existing development context.
- A normal contextual homepage link leads directly to the slowdown guide alongside the existing storage-guide entry.
- Guides hub has a descriptive title/heading and a visible editorial-methods section. It explains publisher identity, AI assistance, primary sources, local testing versus documentation review, and a corrections path.
- Both visible bylines and Article author URLs link to that section. No fictional author profile or credential was added.
- Homepage Organization/WebSite and hub CollectionPage/Breadcrumb data describe the visible site. No fabricated software offer, rating, FAQ result or special AI markup.
- Storage datePublished is 2 November 2026, supported by the first successful guide deployment: [Pages run 41490647421](https://github.com/VenkateshDas/pulse/actions/runs/41490647421), completed 2 November at 17:23:21 UTC, from merged PR #98 (`eabf7a1`). Its 1 November source/walkthrough review date remains explicit.
- Existing shared styles supply layout; only paragraph separation was added for the new methods section. No new framework, font, tracking vendor or content generator.
- Static validation now checks direct homepage guide links, publisher identity relationships, hub guide listings, byline destination and publication metadata.

## Evidence prepared

The [audit](seo-search-demand-audit-2026-11-03.md) records the observed discovery gap, tool recommendations, current primary guidance and content queue. The [CSV and Trends observations](seo-evidence/README.md) preserve public keyword evidence and data-quality limits. [System Data](articles/what-is-system-data-on-mac.md) and [startup](articles/mac-slow-startup.md) drafts have inline primary sources and explicit verification limits. Startup is conditional because historical demand spikes do not establish a current trend.

## Verification

- `python3 landing/scripts/check-pages.py`: pass, six pages and four sitemap URLs, assets/fragments/metadata/schema.
- `node landing/scripts/check-analytics.cjs`: pass, existing privacy, route, page-view and click contracts.
- `git diff --check`: pass.
- Browser checks: 1440px desktop, 390px and 320px mobile; no document overflow on inspected changed surfaces. Hub listing and byline-to-methods fragment work. Native browser activation confirmed the new homepage-to-slowdown link; a Playwright click only scrolled to it, so it was not treated as proof of navigation.
- Rendered methods paragraphs initially ran together because the global paragraph margin is zero. Added a scoped 16px margin and verified it visually/computationally. Existing page measure and typography remain.
- Homepage console inspection showed no errors. The pre-change public PageSpeed lab runs and their limits are recorded in the audit; they are not a post-deployment ranking claim.
- Review screenshots and private account UI evidence remain under `/tmp/pulse-seo-audit`, outside the public repository.

### Stop-hook padding review

Reviewed all six unique `cramped-padding` findings surfaced by the completion hook (the raw scan repeats the identical list/decision-row findings). All were false positives in the existing layout, not SEO-pass regressions:

- Homepage storage, capabilities and home-guide colored sections have 80px desktop / 64px mobile block padding, with inner `.wrap` side gutters of 80px / 24px at 1440px / 390px.
- The approach section applies the same 80px / 64px vertical inset to its inner wrapper and has the same side gutters.
- All eight capability list rows have 16px padding above/below their text. At desktop the list is a clipped screen-reader equivalent; it becomes visible on mobile with that padding intact.
- All three storage-guide decision rows have 24px vertical padding; their first text starts 25px below the 1px top border, on desktop and mobile.

Rendered screenshots and computed styles confirm adequate spacing. Preserved the intended layout. Used the skill's `hooks ignore-value` command to persist `cramped-padding=*` exceptions scoped to only `landing/index.html` and `landing/guides/whats-taking-up-space-on-mac/index.html`, with the measurements as reasons. No global rule/file ignore was added. The follow-up detector scan returned no findings. No confirmed defect or uncertain finding remains from this hook review.

## Search actions already completed

Indexing requests for both guides and the hub were accepted. The sitemap submission was accepted, but its status table continued to show Couldn't fetch. Homepage indexed state and canonical are correct. AI inclusion inherits Include; no setting was changed. These account actions do not mean the prepared website changes are deployed.

## Release status

Prepared on `codex/seo-demand-audit`. Required CI and owner merge review precede publication. No new article HTML or sitemap URL has been added. No new account, paid plan, domain, campaign or external message was created. After an approved merge, verify Pages deployment and public metadata/byline links, then recheck search processing without repeatedly requesting the same URLs.
