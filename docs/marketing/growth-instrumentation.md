# Growth setup — 31 October 2026

## Approved scope and rollout

Finish the MailerLite journey, set up free PostHog using the Pulse Google account, and prepare Search Console. PR #94 merged with explicit owner approval; Pages run 41185896105 deployed the landing and branded thank-you. Follow-up code requires its own CI and explicit merge approval. Search Console verification and sitemap submission are pending deployment of its meta tag. No guide URLs are published.

## Signup evidence

MailerLite double opt-in is enabled. The saved custom confirmation URL is https://venkateshdas.github.io/pulse/thanks/ . A fresh authorized alias signup received confirmation in Gmail and reached that branded page. A separate owner-approved test update used an exact email filter and a final audience of one. Its recipient Unsubscribe link displayed success, and the dashboard shows the test record Unsubscribed. No other recipients received a campaign. No second suppression message was sent; duplicate-active signup and other inbox providers remain untested. Default newsletter wording in the confirmation email remains provider-locked. Sending beyond the trial is not established by this test.

## PostHog account and minimal collection

Organization Pulse; project Pulse website (328381), EU cloud, Google sign-in with the existing Pulse account. Free plan selected; no card added. Timezone Asia/Kolkata. Project IP anonymization enabled. Autocapture, replay, heatmaps, console logs, performance capture, exceptions, surveys and web vitals disabled.

Static public config contains only the ingestion token and regional host; the token grants event ingestion, not project read/admin access. No private API credential exists in the repository. Native browser fetch uses the documented batch endpoint; no SDK, cookie, framework or build dependency added. A text/plain JSON request avoids preflight cancellation during navigation. Failure never blocks signup.

Privacy controls use existing Pulse buttons. Collection defaults off; allowing saves a random UUID and choice in localStorage. Rejecting removes the UUID and stops capture, including other open tabs receiving the storage event. Global Privacy Control and Do Not Track keep collection off. Storage failure also leaves collection off. The thank-you page has no analytics.

Allowed events: `$pageview`, `early_access_click`, `waitlist_form_open`, `preview_theme_selected`. Each sends a fixed canonical page, a coarse source category and a test boolean; clicks may add a fixed placement or theme. No email, typed text, full referrer, arbitrary query string, fragment, filesystem data or subscriber identifier is included. Person-profile processing and GeoIP enrichment are disabled. Source direct also covers missing/blocked referrers; it is not certain attribution. Preview theme measures clicks; keyboard-only changes are not captured.

Local traffic is marked `is_test: true`. Use `?pulse_test=1` for deliberate public QA; only that boolean is sent, never the query itself. The page path is currently fixed to the sole public landing page; add an explicit canonical allowlist when guide pages exist. No session duration, bounce rate, replay or automatic cross-page attribution is implemented.

## Dashboard

[Pulse growth — consenting visitors](https://eu.posthog.com/project/328381/dashboard/1071756) is pinned and set as default. Three native daily distinct-browser charts cover pageviews, early-access clicks and form navigation attempts. Every chart includes `is_test = false`. Unique browser IDs are not people; consent and blockers make coverage incomplete. Summing daily uniques is not period-unique traffic. Zero public data before deployment says nothing about demand. MailerLite is the source of truth for confirmed subscribers; no signup-confirmed event is emitted.

## Search Console

URL-prefix property https://venkateshdas.github.io/pulse/ was added under the Pulse Google account. The provider-issued public meta tag is in landing/index.html. A sitemap contains only the live canonical homepage; the noindex thank-you is excluded. After approval/deployment: verify via the HTML-tag method, submit https://venkateshdas.github.io/pulse/sitemap.xml, inspect the homepage and request indexing if appropriate. Do not claim verified or indexed before the provider confirms it.

## Validation

Run `node landing/scripts/check-analytics.cjs`, JavaScript syntax checks, local asset/fragment/sitemap validation and `git diff --check`. Native Node smoke tests cover default-off capture, GPC, blocked storage, event payloads, no query/referrer leakage, repeated permission, withdrawal and cross-tab opt-out. Browser opt-in/opt-out, Home theme click and hosted-form navigation were exercised; PostHog installation and Activity visibly show the four expected event types. Signup/confirmation/update/unsubscribe evidence is above. Required CI and final live verification remain deployment gates.

References checked 31 October 2026: [PostHog Capture/batch API](https://posthog.com/docs/api/capture), [collection controls](https://posthog.com/docs/privacy/data-collection), [Search Console ownership](https://support.google.com/webmasters/answer/9008080?hl=en).
