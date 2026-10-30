# Pulse waitlist landing page

## Status and scope

The October 30 waitlist-first decision supersedes the download-first marketing sequence. Landing preview first; PostHog, Search Console and MailerLite are the agreed three-service stack. Apple signing and public-build validation are deferred to launch. Product-safety work remains required before inviting people to use cleanup.

This change implements the landing page only. It is not deployed, collecting emails, or measuring visitors until separately configured and approved. It contains no analytics SDK, no email input, no storage of subscriber data and no provider API keys. Existing GitHub releases are not deleted or hidden; only website download CTAs are removed.

## Design

A person with a storage or slowdown question, reading in an ordinary bright workspace, should get a calm, legible explanation. Use Pulse's existing light canvas, dark ink and green accent from DESIGN.md. The hero leads to an interactive, explicitly illustrative product preview, three user questions, the understand/review/choose approach, early-access invitation and FAQ. No invented testimonials, savings, pricing or actual system readings. Preview switches are user-controlled; there is no rotating demo or sampled animation.

Static HTML, CSS and JavaScript remain compatible with the existing Pages upload. There is no new build dependency. The native app is unchanged. The referenced docs/product_spec.html remains absent, so its Lessons section could not be read; PRODUCT.md, DESIGN.md and the user-provided constraints informed this marketing-only change.

## Next: connect MailerLite

1. Founder creates/approves a MailerLite account and chooses the sender identity. Confirm the current free-plan allowance and account approval requirements. Never post credentials into chat or git.
2. Create a `Pulse early access` group and a signup form. Keep email required, and make the Mac-problem question optional. Explain invitations/occasional updates and make no launch-date or pricing promises.
3. Enable double opt-in. Configure and test confirmation email and confirmation/success screens. A submission is not yet a confirmed subscription.
4. Review sender authentication requirements. The existing github.io address is the site host, not an email-sending domain. If the service requires a verified owned sender domain, resolve that before launch; do not promise a zero-cost sending setup regardless of provider requirements.
5. Use the form's HTTPS **Share URL**, documented by MailerLite. Paste the exact public URL into `landing/config.js` as `waitlistUrl`. Do not put a private API token there. A hosted form is deliberate: it handles validation, abuse protection, provider failures and confirmation, without a custom backend.
6. Review the privacy notice and provider form disclosures. The script switches the page from closed-signup copy to MailerLite processing information when a valid HTTPS URL is configured. Invalid/missing config fails closed. The setting accepts branded HTTPS form URLs too; maintainers must verify ownership/destination before publishing.
7. Use a founder-approved test address to verify the full flow: CTA → hosted form → validation → submission → confirmation email → confirmed subscriber → unsubscribe. Check duplicate signup, wrong address, inaccessible provider and mobile keyboard behavior. Don't claim live signup from a local navigation-only test.
8. Preview and obtain user approval; merge only after required CI and explicit approval. Pages deploys landing changes when merged.

Official provider references:
- https://www.mailerlite.com/help/how-to-add-a-form-to-your-website
- https://www.mailerlite.com/help/how-to-use-double-opt-in-when-collecting-subscribers

## Later: measurement and content

- Add PostHog after account/project creation and privacy/consent choices. Track anonymous CTA location and preview selection; keep emails and free text out of analytics/replays. Provider records are the source of truth for confirmed subscriptions. A click or return-page visit must not be counted as a confirmed signup.
- Verify a Search Console URL-prefix property for https://venkateshdas.github.io/pulse/ using the generated ownership token/file. Submit a sitemap after public guide URLs exist. No GA4 or Tag Manager is required for this pilot.
- Build the guide layout and one source-backed, tested article before expanding to five. Do not add dead guide links or pretend unpublished articles exist.
- This version has no tracking snippets. Its privacy statement must change in the same PR that introduces analytics, replay or additional processors.

## Review checks

Verify desktop and narrow mobile layouts, no horizontal overflow, working anchors, all three preview panels, arrow/Home/End tab navigation, visible focus, FAQ expansion, no download/offered-price claims, and truthful missing-config state. JavaScript syntax and local link checks supplement browser review. No native app code changed; required repository CI still applies.

Local preview: `python3 -m http.server 8765 --directory landing` from the repository root. This serves a development preview only.

## Validation evidence — October 30

- Browser review at desktop 1280px and mobile 390px/320px: no horizontal overflow at checked widths; all three previews and keyboard Arrow/Home/End navigation verified; native FAQ expansion and closed-signup click feedback verified.
- JavaScript syntax, local asset/fragment targets, unique IDs and removed download/placeholder checks pass.
- Independent read-only Cavecrew review reported no issues.
- Full-page desktop/mobile review screenshots saved locally; live MailerLite flow remains untested and blocked on account/form setup.
- User approved updating Impeccable for future sessions; updater reported v4.8.0 installed. Local skill hooks are not included in the website PR.
