# Search-demand evidence — 3 November 2026

These files contain public keyword/trend observations, not website visitors or personal data. Authenticated Search Console and PostHog UI exports remain in the local audit working directory, outside git. Relevant aggregate results are recorded in the [audit](../seo-search-demand-audit-2026-11-03.md).

- `keywords-us-2026-11-03.csv`: first 15 suggestions from each of three Semrush US free-tool lookups. Of 45 observations, 10 cooking results were excluded. The remaining 35 observations cover 34 distinct phrases; `system data mac storage` appears in two source reports. Its page owner is consistent. Other off-topic/commercial results remain explicitly marked exclude/hold rather than silently counted as opportunities.
- `trends-us-initial.json`: exploratory 12-month comparison. Broad `mac slow` phrasing is ambiguous; do not rank priorities from it. Zeros for narrow developer terms are unresolved demand, not proof of no searches.
- `trends-us-90d.json`: recent topical comparison and related-query observations. The feed includes irrelevant suggestions; all are preserved to expose the data-quality problem. Relevant rising-query percentages are leads, with unknown absolute bases.
- `trends-us-specific-queries.json`: 12-month cross-check of four specific phrases after the large startup-keyword estimate needed scrutiny. Contains the displayed averages and weekly chart rows, including the latest potentially partial week.

The CSV contains vendor estimates for monthly searches, keyword difficulty and CPC. Database month/window was not shown. `I` and `C` are the vendor's informational/commercial labels. Source URLs and retrieval date are recorded per observation. Do not sum variants, treat KD as a Google metric, or imply these are verified current-month counts.

Trends files preserve text visible in chart tables via a read-only browser DOM inspection. Query settings are in the source URL. Trends may omit the default `today 12-m` parameter in its final URL; the UI showed Past 12 months. Numeric values are a normalized interest index on the comparison's shared scale, not searches or percentages. Comparisons with different terms/date ranges are not on the same scale. Unicode direction marks in date labels are retained from the source.

The CSV's future page paths identify an editorial owner. Those pages are not thereby published. Drafts and research leads are excluded from the public sitemap.
