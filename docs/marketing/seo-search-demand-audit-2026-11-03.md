# Pulse search discovery, SEO and answer visibility audit

Researched 3 November 2026. Market: United States first; publish useful English content for readers worldwide, as confirmed by the owner. Baseline website commit: `8b1c0c556782a4bc09b39307be8362a69ed24abd`. This report separates observed account/site evidence, public keyword estimates and editorial decisions.

## What explains the lack of visitors so far

The strongest observed issue is **guide discovery**. The homepage is indexed, but both articles and the Guides hub were unknown to Google when inspected. The first guide was publicly deployed on 2 November; the second on 3 November. These pages have had very little time to be discovered. We cannot conclude that their content failed, or that there is no audience.

| Evidence checked directly | Observed result | Meaning and limitation |
| --- | --- | --- |
| Search Console, Web performance, default three-month selection | Reporting chart covers 30 October–1 November: 1 impression, 0 clicks, average position 9; query table has no rows | Almost no measured search exposure yet. One impression cannot establish normal ranking or CTR. No usable first-party keyword sample exists |
| Performance → Pages | Homepage: 1 impression, 0 clicks; sole page row | The report does not establish exposure for either guide; it predates the second guide |
| Homepage URL Inspection | URL is on Google; last crawl 31 October, Googlebot smartphone; successful fetch; indexing/crawl allowed | Google-selected canonical is the inspected homepage URL. The entire site is not blocked from Google |
| Both article URLs and Guides hub, indexed-state inspection | Not indexed; URL unknown to Google; no referring sitemap detected | These URLs cannot currently earn normal Google article traffic. This is a state observation, not proof of a ranking penalty |
| New slow-Mac article, live test | Available to Google; page can be indexed; one valid breadcrumb item | Current accessibility and valid breadcrumb detection do not mean the URL has entered the index |
| Existing sitemap report | Couldn't fetch; unknown type; 0 discovered pages | The submitted URL is correctly under `/pulse/`, despite its abbreviated table label `/sitemap.xml` |
| Sitemap public HTTP/XML check | HTTP 200, application/xml, four correct canonical URLs; static checks pass | No malformed XML or wrong project-path URL found. Public fetch success is not proof of Google's sitemap processing |
| Homepage index details | Sitemaps: temporary processing error | Supports treating the sitemap discrepancy as unresolved processing/fetch trouble; it does not identify its root cause |
| Search Console Settings → Search generative AI | Inherit from parent; **Current control: Include** | No change needed. Inclusion is eligibility, not proof of AI impressions or citations |
| Existing PostHog growth dashboard, last 7 days | Page-view and early-access-click tiles: no matching events; tests excluded | No measured non-test activity in those tiles at inspection. This is not a census of people: opt-outs, browser signals, blockers and failed requests reduce coverage |

Search Console sources are the authenticated [property](https://search.google.com/search-console?resource_id=https%3A%2F%2Fvenkateshdas.github.io%2Fpulse%2F), [Web performance report](https://search.google.com/search-console/performance/search-analytics?resource_id=https%3A%2F%2Fvenkateshdas.github.io%2Fpulse%2F) and [sitemap report](https://search.google.com/search-console/sitemaps?resource_id=https%3A%2F%2Fvenkateshdas.github.io%2Fpulse%2F). The existing [PostHog dashboard](https://eu.posthog.com/project/328381/dashboard/1071756) is the measurement source. Private account UI exports remain outside the repository; this report contains only the relevant aggregates.

### Discovery actions completed during this audit

Google accepted one indexing request for each article and the Guides hub. Both article requests and the hub request returned “Indexing requested.” The sitemap was resubmitted once and accepted, but the table still showed Couldn't fetch afterward. Do not describe the sitemap as fixed or these pages as indexed. Repeated requests do not advance Google's queue.

Next check: inspect these exact canonical URLs again after processing has had time to run, and check the sitemap's last-read/status. If the error persists, use the report's fetch details and Crawl Stats/host availability evidence before changing hosting or sitemap format. Do not rotate sitemap URLs, repeatedly submit, remove canonical tags or create a redundant sitemap to disguise the error. Google does not guarantee crawling or indexing. [Google's indexing FAQ](https://developers.google.com/search/help/crawling-index-faq)

## Technical and page-quality audit

Public checks covered the homepage, hub, both guides, sitemap, a deliberately nonexistent guide and the origin-root robots URL. All four public content URLs returned 200. The missing guide returned a real 404. `https://venkateshdas.github.io/robots.txt` returned 404, which is acceptable for a missing robots file. A `/pulse/robots.txt` file would not control the origin-root crawler policy. [Google's robots guidance](https://developers.google.com/crawling/docs/robots-txt/robots-txt-spec)

The site already has a good foundation: server-delivered HTML, unique page titles/descriptions, self-canonicals under `/pulse/`, one H1 per page, crawlable links, image dimensions/alt text, Article/Breadcrumb markup on guides, and a four-URL sitemap. Privacy and confirmation pages deliberately remain noindex and excluded from the sitemap. There is no need to install a framework or an SEO plugin to preserve these properties.

### Mobile PageSpeed laboratory results

| Public page | Performance | Accessibility | Best practices | Basic SEO | LCP | CLS | TBT |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Homepage | 99 | 100 | 100 | 100 | 0.9 s | 0 | 0 ms |
| Storage guide | 100 | 100 | 100 | 100 | 0.9 s | 0 | 0 ms |
| Slow-Mac guide | 100 | 100 | 100 | 100 | 0.9 s | 0 | 0 ms |

These are single-run PageSpeed Insights lab observations on 3 November, emulated Moto G Power, Slow 4G, Lighthouse 13.6.0. All three reported **No Data** for real-user experience. TBT is not field INP. A basic SEO score of 100 says nothing about search demand, originality, backlinks or whether Google indexed the page. The homepage's speed index was 3.5 s; the slow guide's 2.2 s; storage 0.9 s. Small render-blocking/cache/image opportunities exist, but the evidence does not make performance refactoring the first growth priority. [PageSpeed Insights](https://pagespeed.web.dev/), [Google's Core Web Vitals guidance](https://developers.google.com/search/docs/appearance/core-web-vitals)

Public laboratory runs can generate synthetic page loads. Use the pre-audit search baseline above; do not call new audit-window events organic visitors. Future public QA should use the existing `pulse_test=1` flag where the tool allows it.

### Prioritized improvements

| Priority | Finding | Response |
| --- | --- | --- |
| First | Articles/hub unknown to Google; sitemap discrepancy | Indexing requests completed; follow processing rather than assuming a metadata problem |
| First | Homepage title is a brand promise with no clear product category | Approved change names a Mac performance monitor and storage explorer, while keeping development/early-access status explicit |
| First | Homepage links directly to storage but only indirectly to the new slowdown guide | Add an ordinary contextual HTML link to the slowdown article |
| Next | Hub title/H1 are generic; authorship links do not explain who publishes the guides | Clarify the hub and link both bylines to visible editorial methods |
| Next | Homepage/hub lack identity/collection structured data | Add truthful Organization/WebSite and CollectionPage/Breadcrumb data; helps description and consistency, not a guaranteed ranking lift |
| Next | Slowdown article has source review but no native walkthrough | Verify it on a disposable/test environment and add useful original evidence before increasing publication volume |
| Next | Only two articles; many competitors answer the same broad questions | Expand distinct reader tasks with original checked examples; a new generic “10 tips” list has little advantage |
| Later | AI referrals currently fall into the analytics `other` category | Consider fixed coarse hostname categories for ChatGPT/Perplexity under the existing privacy contract; do not ingest arbitrary UTMs, queries or full referrers |
| Unknown | Referring domains, Google link-report completeness, Bing indexing, actual conversions from organic search | Do not invent authority scores or claim backlinks are the proven cause. Inspect these as data becomes available |

The owner approved the bounded website pass in the [implementation design](../superpowers/specs/2026-11-03-search-discovery-design.md). Website changes stay in a PR until required CI and owner merge review. No custom domain or paid account is part of this pass.

## Keywords people use: actual observations, not invented volumes

I queried Semrush's public free tool three times, using US database (`db=us`), and recorded the first 15 visible suggestions per seed: `mac system data`, `mac slow`, and `mac storage`. After removing ten cooking results, the [keyword inventory](seo-evidence/keywords-us-2026-11-03.csv) contains 35 observations covering 34 distinct phrases (one appears in two seed reports). Some observations are intentionally excluded or held for validation.

The numbers below are **Semrush estimated US monthly search volumes**, retrieved 3 November. The tool did not expose its database update month or the exact measurement window; they are not verified November-only counts. KD is the vendor's estimated difficulty, not a Google score or a probability of ranking. Variant volumes overlap and must not be added as independent audiences. [System Data lookup](https://www.semrush.com/analytics/keywordmagic/?db=us&keyword=mac+system+data), [slowdown lookup](https://www.semrush.com/analytics/keywordmagic/?db=us&keyword=mac+slow), [storage lookup](https://www.semrush.com/analytics/keywordmagic/?db=us&keyword=mac+storage)

| Search phrase | US monthly estimate | Vendor KD | Editorial action |
| --- | ---: | ---: | --- |
| how to check mac storage | 8,100 | 51 | Improve the existing storage guide's answer and navigation; no duplicate article |
| how to clear system data on mac | 5,400 | 37 | Support within one System Data guide; address deletion intent honestly |
| what is system data on mac | 4,400 | 16 | Primary query for the next drafted guide |
| why is my mac so slow | 2,900 | 39 | Existing slowdown guide owns this intent |
| system data mac storage | 2,400 | 36 | Supporting wording in the same System Data guide |
| how to clear storage on mac | 1,600 | 32 | Existing storage guide, with honest review/removal boundaries |
| how to reduce system data on mac | 1,300 | 25 | Same System Data guide; do not publish a wording variant |
| how to fix slow mac | 1,300 | 39 | Existing slowdown guide |
| how to stop mac from randomly gaining so much storage | 1,300 | 27 | Future storage-growth brief; needs original dated measurements |
| mac running slow | 1,000 | 39 | Existing slowdown guide |
| why is system data so big mac | 1,000 | 32 | Same System Data guide |
| other users and shared mac storage | 590 | 26 | Distinct future guide if a current walkthrough can add value |

The tool also reports **22,200/month, KD 27** for `how to fix slow boot mac`. That unusually high number deserves corroboration. The targeted Trends comparison shows historical activity but zeros for that phrase in the last four weekly readings. Prepare the draft, but do not promote it as a current surging opportunity or put it first based on that estimate alone.

### What Trends actually supports

Three dated [Trends observations](seo-evidence/) preserve the query strings, settings and underlying chart tables. These are search terms, not selected Google topics; US, Web Search, All categories. Comparison charts have a shared normalized scale; 0 is not proof of zero searches. The newest interval may be incomplete. Google's data are sampled, normalized and sometimes noisy. [Google's explanation](https://support.google.com/trends/answer/4365533?hl=en)

- The initial 12-month comparison used broad phrases including `mac slow`. Keyword-tool results revealed that similarly broad wording can include cooking intent; do not use that chart to rank Mac problems against one another. Docker.raw and Xcode DerivedData were below useful resolution in that comparison, not proven to have no demand.
- The more targeted 12-month US comparison used `how to fix slow boot mac`, `why is my mac so slow`, `what is system data on mac` and `how to check mac storage`. Its displayed averages were 22, 3, 4 and 25 respectively. Recent weekly readings do not establish a rising trend for these phrases. In particular, historical startup spikes do not justify calling that topic trending now.
- A 90-day comparison exposed relevant rising-query leads, including `what is system data on mac storage` (+90%) and `system data mac storage` (+150%), alongside clearly irrelevant queries. These percentages are relative growth from an undisclosed base, not monthly search volume. The System Data cluster is worth investigating because its intent is corroborated by the keyword tool and current reader questions; the entire related-query feed is not trustworthy enough to publish from automatically.
- Memory-pressure and battery phrases were sparse in these comparisons. Current absolute demand and an upward trend remain unverified. Do not rank them using invented estimates.

Current search-result samples for System Data contain Apple documentation, competing Mac utilities and editorial explanations such as Macworld. Startup searches surface Apple's login-item, safe-mode and startup-failure guidance. This is a qualitative landscape check, not a captured, location-controlled Google top-ten ranking. The opportunity is a clearer, tested decision path and original evidence; competitors' technical claims are not treated as sources for our instructions.

## The tools we need

| Tool | What it answers | Use for Pulse | Boundary |
| --- | --- | --- | --- |
| Google Search Console | Are pages indexed? Which queries show our site? Impressions, clicks and CTR | Already verified; primary weekly discovery and performance evidence | Low-volume queries may be omitted; position is an aggregate, and reports lag |
| Google Trends | Is relative interest rising, seasonal or fading? Related-query discovery | Free; compare relevant terms with US, explicit dates and search type | Relative 0–100 values are not monthly searches; broad phrases and sparse data mislead |
| Semrush free keyword tool | Keyword variants, estimated volume, intent and difficulty | Used now; sufficient for a small initial shortlist | Limited results; estimates, unknown visible data freshness, noisy broad matches |
| Google Ads Keyword Planner | Google historical keyword estimates, seasonality and location | Optional independent validation if an account is already available | Current documentation requires completed setup including billing information. Do not activate campaigns or enter payment details merely to finish this audit |
| Bing Webmaster Tools | Bing indexing, query volumes, related/question keywords and AI citation evidence | Recommended next free search property; connect/verify deliberately | Bing volumes are not Google volumes; account access was not verified here |
| PageSpeed Insights / Lighthouse | Loading and basic technical/accessibility checks | Used for homepage and both articles; repeat after material site changes | Lab scores are not actual rankings or field-user pass rates |
| Existing static checker; optionally Screaming Frog | Broken links, canonical/indexability and metadata regressions | Keep repository checker in CI; a crawler is useful as the site grows | Screaming Frog's free edition currently crawls up to 500 URLs; no install needed for this six-page site |
| Existing PostHog + MailerLite | What happens after a visit? Clicks and confirmed subscriptions | Keep existing services and privacy controls | Per-page random IDs do not identify unique people or link a cross-page funnel. Form opens are not confirmed signups |
| Ahrefs Free / a paid keyword suite later | Independent site audit, competitor/link and keyword research | Alternative or occasional second source, not another mandatory subscription | Vendor scores remain estimates; account verification/permissions need deliberate setup |

Use the free stack first. If it becomes necessary to research many competing pages or export thousands of keywords, choose **one** paid suite for a bounded research period after budget approval. Buying several overlapping tools will not repair discovery or create original expertise.

Official tool references: [Keyword Planner historical metrics](https://support.google.com/google-ads/answer/3022575?hl=en-GB), [Planner setup requirement](https://support.google.com/google-ads/answer/6325025?hl=en-GB), [Bing keyword research](https://www.bing.com/webmasters/help/keyword-research-628070b6), [Screaming Frog limits](https://www.screamingfrog.co.uk/seo-spider/faq/), [Ahrefs free tools](https://ahrefs.com/free-seo-tools).

## SEO and AEO: the publishing standard

For Google, AEO/GEO rests on the same discovery and quality foundation as Search. An indexed, snippet-eligible page and inclusion in Search generative AI features matter. Special AI schema and llms.txt do not provide a Google ranking shortcut. Answering the reader clearly is useful; there is no prescribed AI paragraph length, keyword density or requirement to split an article into tiny chunks. [Google's current generative AI guidance](https://developers.google.com/search/docs/fundamentals/ai-optimization-guide)

For each article:

1. Give the direct answer early, then the conditions, steps and stopping point needed to use it. Use headings and a contents list for humans, without repeating keywords unnaturally.
2. Include original evidence where it matters: a tested procedure, disposable fixture, annotated real screenshot or a reproducible before/after observation with hardware/version/workload. Label fictional values. No invented personal story, expert credential or benchmark.
3. Link primary technical sources next to claims. Explain which guidance is our editorial method and which is vendor-documented behaviour.
4. Show the publisher/byline, source-review date and tested environment. Explain AI assistance and testing limits honestly. Update dates for real changes; do not refresh dates daily to simulate freshness. [Google's authorship and process guidance](https://developers.google.com/search/docs/fundamentals/creating-helpful-content)
5. Use a unique descriptive title, truthful description, correct canonical, one clear H1, readable semantic HTML, descriptive internal links and appropriate image alternatives/dimensions. Preserve URLs during copy improvements.
6. Use Article and Breadcrumb metadata matching the visible article, with truthful dates and authorship. Never invent ratings, offers or review credentials. FAQ content can help readers, but Pulse should not expect Google's restricted FAQ rich results. HowTo rich results are deprecated. [Article documentation](https://developers.google.com/search/docs/appearance/structured-data/article), [FAQ/HowTo changes](https://developers.google.com/search/blog/2023/08/howto-faq-changes)
7. Make the article useful without installing Pulse. Describe the in-development product accurately, after the manual answer, with one relevant invitation.

For answer-engine measurement, retain the verified Google Include setting. The [Google generative AI report](https://support.google.com/webmasters/answer/16984139) may not appear without sufficient impressions; it was not present in this property's visible navigation. It is not valid to infer zero citations from that absence. Bing's [AI Performance documentation](https://blogs.bing.com/webmaster/2026/10/introducing-topics-portfolio-beta-in-ai-performance/) describes citation/topic evidence when sufficient site data exists. Citation counts, organic impressions and website clicks answer different questions and must not be added together.

OpenAI documents OAI-SearchBot as its search crawler; GPTBot is a separate training control. Do not advise enabling training as a prerequisite for search visibility. The current root robots response does not establish a block, but this audit did not inspect server-side AI crawler logs. OpenAI also documents ChatGPT referral tagging; analytics currently does not classify that separately. [OpenAI crawlers](https://developers.openai.com/api/docs/bots), [publisher referral documentation](https://help.openai.com/en/articles/12627856-publishers-and-developers-faq)

## Content queue and evidence required

| Order | Primary reader task | Deliverable | What earns publication |
| --- | --- | --- | --- |
| Now | Find storage usage / investigate a slow Mac | Improve and get the two existing guides discovered | Approved website pass, CI and owner merge review; verify indexing after processing |
| Next | Understand System Data and choose an appropriate action | [Complete System Data draft](articles/what-is-system-data-on-mac.md) | Current Settings/Finder/device-backup/iCloud labels checked; disposable examples; reviewer verifies deletion consequences and source boundaries |
| Next research | Explain storage that keeps filling up | Brief: dated observations before and after a controlled app workload | Actual repeat measurements, permission gaps and a stated scope; do not claim exact disk accounting |
| Conditional | Separate slow boot from slow activity after login | [Complete startup draft](articles/mac-slow-startup.md) | Revalidate current demand, check login-item restoration and both documented safe-mode paths; never restart the owner's Mac to manufacture evidence |
| Later | Explain Other Users & Shared storage | Distinct brief | Test accounts/disposable data; preserve other users' files and make ownership clear |
| Later | Understand memory pressure and swap | Distinct explanatory brief linked from slowdown guide | Current query validation and real annotated Activity Monitor example; no universal RAM threshold |
| Hold | Xcode/Docker disk growth; battery or update-specific slowdowns | Research leads | Owner's earlier general-Mac priority remains. Validate niche demand and current official instructions; no trend claim from sparse data |

The drafts use the research-pipeline evidence discipline and humanizer prose review, with the existing Pulse help article format. The pipeline's autobiographical curiosity-note conventions are inapplicable to product instructions. Its external article template was already unavailable in the prior guide work; no observation or credential was invented to imitate it.

Drafts stay outside `landing/` and the sitemap. They are prepared content, not published or fully tested guides. A documented local walkthrough is a real publication gate, not a checkbox satisfied by an AI prose review.

## Repeatable weekly decision process

Export Search Console pages and queries for comparable complete periods, with geography/device filters recorded. Keep the newest partial/lagging days out of comparisons. Record index status separately from performance. Do not infer failure from one impression or percentage changes with tiny denominators. [Search Console metrics](https://support.google.com/webmasters/answer/7576553)

For new topic research: start with the reader problem, collect actual phrases, filter irrelevant meanings, record vendor/source/date/country/window, inspect current results, and group phrases into one task. Compare the topic in Trends over 12 months and a recent window. Write only when the article has distinct utility and evidence beyond existing pages. A rising related query is a lead; it is not an instruction to auto-publish.

Use the resulting evidence to choose an action:

- Not indexed: diagnose discovery, canonical/indexability or indexing quality before tuning click-through copy.
- Indexed but barely shown: assess topic fit, depth, original evidence and relevant discovery links; inspect actual queries as they arrive.
- Relevant impressions with weak clicks over a useful sample: compare title/answer intent and the live search result; improve the existing page.
- Visits but no product interest: assess whether the guide solves the problem and whether the contextual product invitation fits.
- Form handoffs without confirmed subscriptions: investigate the form/confirmation journey using provider evidence, without pretending separate counts form an attributable conversion rate.

Keep counts for search impressions/clicks, page views, guide-product clicks, form handoffs and new confirmed subscribers separate. The first milestone is that the intended guides are indexed and begin receiving relevant impressions. No fixed visitor target, ranking deadline or statistical uplift is supported by this baseline. Relevant community sharing and genuine project documentation can help people discover useful work; no messages, promotional posts or backlink purchases were sent or authorized by this audit.

## Verification and handoff

Website validation and PR status are recorded in the companion implementation record before handoff. Existing older setup notes remain historical evidence; this audit supersedes their now-stale statements about a homepage-only sitemap, opt-in identifiers and no published guides. No analytics access, billing, hosting domain or signup behaviour was changed during this pass.
