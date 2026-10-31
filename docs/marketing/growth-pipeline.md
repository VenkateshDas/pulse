# Pulse growth pipeline — execution checklist

Updated 31 October 2026. Current operating plan for the approved waitlist-first strategy. This supersedes beta-download, optional-AI and beta-activation recommendations in the October 28 marketing plan/backlog. The landing and app are prepared separately; public launch, signup and analytics are not yet verified live.

## Sequence and ownership

| Step | Deliverable | Founder input | Completion evidence |
|---|---|---|---|
| 1. Capture interest | MailerLite hosted form with double opt-in | Pulse email/account ownership; sender verification | Test submission, confirmation, confirmed record and unsubscribe all work |
| 2. Measure interest | PostHog traffic and explicit CTA events | Project creation, region choice and public project token/host | Test events arrive once; privacy choices work; no email/free text captured |
| 3. Enable search discovery | Search Console URL-prefix verification; sitemap of published URLs | Google account/property verification token | Verified property; deployed canonical pages accessible; sitemap accepted |
| 4. Publish useful help | One thoroughly checked guide, then a small related cluster | Review factual demonstration and public copy | Useful manual answer, sources, tested steps, relevant waitlist CTA |
| 5. Learn weekly | Short acquisition and intent review | Optional subscriber feedback; founder-approved distribution | Decide one improvement from evidence rather than increase output automatically |

Start with step 1. Prepare later steps in parallel where account access is unnecessary. No paid tool, custom email backend or autonomous publishing engine is needed for this pilot. Existing GitHub Pages hosting is the starting point; a custom domain can be decided before broader promotion to avoid unnecessary URL migration.

## Current verified repository state

- `landing/config.js` has an empty `waitlistUrl`; signup fails closed. No subscriber collection or analytics SDK is enabled.
- The configured canonical is `https://venkateshdas.github.io/pulse/`. This is the intended existing-host address, not proof that the new landing is deployed.
- `.github/workflows/pages.yml` deploys landing changes from main. PR #94 remains subject to required CI and explicit user approval before merge.
- No guide directory, sitemap or Search Console verification file/tag has been added. Do not claim unpublished URLs exist.
- Native UI marketing proof uses fictional fixtures. Do not collect personal Mac screenshots for guides without a deliberate privacy review.
- `docs/product_spec.html` remains absent; the supplied AGENTS constraints and current product documentation govern product claims.

## Step 1 — exact signup setup

Founder signs in privately; passwords, recovery codes and provider API secrets stay out of chat/git. Create a MailerLite group named **Pulse early access** and a hosted signup form.

Suggested form copy:

> **Know when Pulse is ready.**
>
> Join the early-access list for launch updates and an invitation when testing opens. Pulse helps you investigate storage and app activity before choosing your next step.
>
> **Email** — required.
>
> **What would you most like help with on your Mac?** — optional: storage, slow apps, battery, everyday controls, or another problem.
>
> **Join early access**
>
> Early-access invitations and occasional Pulse updates. Unsubscribe at any time. Joining does not require payment or guarantee a testing place or launch date.

Enable double opt-in. Confirmation email: **Confirm your Pulse early-access signup**. Confirmation instruction: **Confirm your email to join the Pulse early-access list. If you didn’t request this, ignore this email.** Confirmed screen: **You’re on the list. We’ll email when there’s news or a testing invitation.** Do not invent subscriber counts or launch urgency.

Verify sender identity/domain as required by the account. A github.io site is not an owned email-sending domain. Obtain the public HTTPS form Share URL, then configure `landing/config.js` and review the existing privacy text together. Test mobile, invalid/duplicate submission, delivery, confirmation, confirmed group membership and unsubscribe with a founder-approved address. A successful navigation is insufficient.

## Step 2 — small measurement contract

Start with explicit events, session recording and broad autocapture disabled. Review collection/consent, retention and the public notice before enabling. Do not identify subscribers in PostHog or send emails, typed answers, arbitrary query strings or full external URLs. Treat client-side analytics as incomplete due to blockers and collection preferences.

| Event | Allowed context | Question answered |
|---|---|---|
| Page view | Approved page path; coarse approved acquisition source | Which pages attract visits? |
| `early_access_click` | Fixed CTA position and page path | Which invitation gets attention? |
| `waitlist_form_open` | Page path | How often do people leave for the hosted form? |
| `preview_theme_selected` | Light or dark | Do visitors explore product proof? |
| `guide_product_click` | Published guide slug | Which helpful article creates product interest? |

An event represents what the browser observed. `waitlist_form_open` means an outbound navigation attempt, not proof the provider loaded. Anchor clicks to the signup section are not hosted-form opens. Never emit a confirmed-signup event from a click or return-page view.

First dashboard: visitors/page views by page and source; unique visitors clicking early access; hosted-form navigation attempts; guide-to-product interest. MailerLite is the source of truth for **new confirmed subscribers**. Keep aggregate subscriber growth separate from browser funnels until reliable, privacy-reviewed attribution exists; do not divide unrelated weekly counts and call the result a conversion rate.

## Step 3 — search and keywords

Create a URL-prefix Search Console property for the final published base URL. For the current GitHub project path, HTML-tag verification avoids relying on a verification file placed at the domain root. Add only the token supplied by the owner, deploy, then verify. A custom-domain property can use DNS if an owned domain is chosen later.

Check canonical URL, indexability and internal links. Publish a sitemap containing only live canonical URLs after guide URLs exist; a project-site sitemap lives under `/pulse/`. A site under this path cannot set domain-root robots.txt policy from its landing folder. Use page metadata when needed. Do not request indexing of drafts or local previews.

Use Search Console for queries, impressions, clicks, CTR and average position once Google has data. Average position is an aggregate, not a guaranteed fixed rank. For prelaunch research use current search results and primary sources, then validate topic choice with actual query data. Search demand and difficulty remain unknown; no paid keyword suite or GA4/Tag Manager is required for the initial pilot.

## Step 4 — first content batch

Initial audience hypothesis: developers on storage-constrained Macs. Each article solves the problem without requiring Pulse; product proof and a relevant early-access invitation follow the answer.

1. **Xcode DerivedData: what it contains and when to remove it.** First draft. Explain actual configured location, regenerated outputs and rebuild/indexing cost. Distinguish archives, simulator state and source/package changes. Verify current Xcode steps on a disposable sample project before publication.
2. **Why Docker.raw is large on Mac.** Distinguish virtual maximum from allocated space and inspect Docker-managed usage. Verify current official Docker instructions; avoid blanket disk-file deletion advice.
3. **Mac storage keeps filling up: how to find what changed.** Explain dated observations and permission/measurement limits. Demonstrate only workflows available in the promoted app version.

Use the October 28 backlog as research leads, not publication-ready copy. Replace beta-download/AI CTAs with the approved early-access offer. No invented keyword volume, guaranteed rankings or guaranteed space recovered. Draft one guide, test its advice, review it, then build the small guide layout and publish through the existing PR workflow. Add the other two only when they contribute distinct value.

## Weekly operating loop

Record date range, published URLs, Search Console indexing/query evidence, PostHog visits and CTA interest, new MailerLite confirmed subscribers, and top voluntary problem themes. Keep subscriber PII in the provider, not repo reports. Empty datasets are **not available yet**, not zero demand.

Choose one action: fix indexing when discovery is absent; improve headline/answer when relevant impressions get weak clicks; clarify the offer when readers engage but do not navigate to signup; investigate form/delivery friction when signup attempts do not yield confirmations. Low counts are directional evidence, not statistically reliable results. Distribution drafts can be prepared; no messages or community posts are sent without explicit instruction.

## Current official references

Checked 31 October 2026; provider limits can change. MailerLite's pricing currently lists 250 free subscribers and 2,500 emails/month. PostHog currently lists 1 million free analytics events/month and no credit card required to start. Do not add a paid billing method for this pilot.

- [MailerLite pricing](https://www.mailerlite.com/pricing)
- [MailerLite double opt-in](https://www.mailerlite.com/help/how-to-use-double-opt-in-when-collecting-subscribers)
- [PostHog pricing](https://posthog.com/pricing)
- [PostHog collection controls](https://posthog.com/docs/privacy/data-collection)
- [Search Console ownership verification](https://support.google.com/webmasters/answer/9008080?hl=en)
- [Search Console performance report](https://support.google.com/webmasters/answer/7576553?hl=en)
