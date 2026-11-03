# Pulse search discovery and editorial improvements

Date: 3 November 2026. Website pass approved by the owner in chat on 3 November 2026. Scope: the existing static website, US-first search research and worldwide English help content. Preserve the current redesign and early-access product state.

## Evidence and objective

Search Console reports 1 impression, 0 clicks and no query rows for the reported 30 October–1 November period. Both published guides were unknown to Google on inspection today. The slow-Mac guide passed Google's live indexability test. The existing sitemap reports “Couldn't fetch,” although the public XML returns HTTP 200 and lists four canonical URLs. Indexing requests for both guides have now been accepted; this does not establish indexing.

The homepage's mobile PageSpeed laboratory run scored performance 99, accessibility 100, best practices 100 and SEO 100. There is no field-user performance dataset. The objective is easier discovery and a clearer useful answer, not an arbitrary SEO score or guaranteed traffic.

## Approaches

1. **Recommended: improve discovery and existing pages, then publish a small tested cluster.** Use current hosting, free tools, existing styles and PR review. Low cost; indexing and readership still take time.
2. **Buy a keyword suite and expand research immediately.** More competitor and keyword coverage, but creates recurring cost before acquisition is established. Consider later; no purchase in this scope.
3. **Publish a large batch around trends.** More pages quickly, but weak original evidence, overlap and maintenance risk. Reject this approach.

## Exact first website pass

- Homepage title: `Pulse — Mac performance monitor and storage explorer`.
- Homepage description: `Understand CPU activity, memory pressure and disk usage with Pulse, a native Mac app in development. Explore the previews and join early access.`
- Keep the existing hero heading and visual design. Revise its description to: `A native Mac performance monitor and storage explorer. See CPU activity, memory pressure and busy apps with context for your next decision.`
- Add a normal HTML link to the slow-Mac guide beside the existing storage-guide entry. Preserve the guide URLs.
- Guides index title: `Mac storage and performance guides | Pulse`. Heading: `Mac questions.` / `Practical answers.` Intro explicitly names storage, slowdowns and built-in Mac tools.
- Add a visible `How we write and check these guides` section to the Guides hub. Explain the Pulse organization byline, use of primary documentation, AI-assisted drafting, distinction between documentation review and local testing, fictional examples, and correction through the public repository. Claim no unperformed expert review or testing.
- Link the visible Pulse bylines on both articles to that section. Add the same author URL to Article schema. Add a truthful datePublished to the storage guide only if its first public publication date is supported by deployment history; otherwise leave it unset. Preserve historical reviewed dates unless substantive content changes.
- Add Organization/WebSite JSON-LD to the homepage, and CollectionPage/BreadcrumbList metadata to the hub, matching the visible product and links. No fake ratings, prices, release availability, FAQ-rich-result promises or special AI schema.
- Expand the existing static-page checker to verify the introduced identity metadata, hub fragment and direct homepage links to both guides. Keep existing analytics/privacy checks.

## Content prepared separately

Research and edit two Markdown drafts: (1) what System Data means and how to investigate it, (2) slow Mac startup versus slow activity after login. Each has one distinct intent, inline primary sources, an immediate answer, useful decision steps and a publication verification checklist. Drafts do not enter the sitemap or public site. Local walkthroughs and factual review precede publication.

## Validation and release

Run static metadata/link/sitemap and analytics checks, plus git diff validation. Inspect changed homepage/hub/bylines at desktop and mobile widths. Use the protected-main PR workflow; green CI and owner merge review precede deployment. Search Console requests and sitemap status are recorded separately from code changes. Do not create paid accounts, change domains or install broad analytics.

## Explicit boundaries

No keyword stuffing, duplicated articles for wording variants, manufactured testimonials, invented benchmarks or mass publishing. No llms.txt file for Google: its current documentation says Google ignores it. No project-path robots.txt masquerading as an origin-root policy. The missing origin-root robots.txt returns 404 and is not a crawl block.
