# Real product landing — 2026-10-30

## Delivered

- Actual Pulse Home captures, Light and Dark; keyboard-operable appearance tabs.
- Actual App activity and app-removal review screens; full-size links for inspection, including on phones.
- AI-generated studio backdrop around the Home screenshot. App UI and telemetry were not generated, retouched or replaced.
- Buyer-focused copy: recognizable Mac questions, concrete native proof, explanation of control, then early-access invitation. No invented testimonials, urgency, performance gains or launch price.
- No frontend dependency or additional service. Removed the obsolete illustrative interface and unused legacy background files.

## Capture provenance

Source: latest local `pulse/dist/Pulse.app`, built on `feat/landing-aligned-app` (PR #95, commit b698bfd). The landing branch does not include that native implementation; do not rebuild the app from this branch expecting the new native UI.

| Asset | Origin |
| --- | --- |
| pulse-home-light.webp | Actual Home, Light mode, technical details collapsed |
| pulse-home-dark.webp | Actual Home, Dark mode, technical details collapsed |
| pulse-activity.webp | Actual grouped App activity, real readings at capture time |
| pulse-app-review.webp | Actual KeepingYouAwake related-file review; nothing removed |
| pulse-studio.webp | `image_gen.imagegen`, background only |

All four app captures: 2288 × 1660, lossless WebP. Only the top 104px OS/window toolbar was cropped from 2288 × 1764 captures. No visible personal paths, SSIDs or private document names. Snapshot readings are not a live browser scan or a performance benchmark. Full prompt/origin is preserved beside each asset in `.json`. Studio output is 1672 × 941, encoded as quality-85 WebP (~18 KB); original generation output remains in the local generated-images directory.

## Sales approach

Used the Sales plugin's `plan-deal-strategy` guidance for an initial buyer motion, plus the copywriting skill. Buyer uncertainty: what is happening, whether actions need judgment, whether the product is real, and what joining entails. Proof is the native interface; the ask is an invitation when ready and an opportunity to influence priorities. Copy explicitly retains caveats around CPU use, related documents, Trash, availability and undecided pricing.

## Validation

- Browser: 1440px, 390px and 320px; no horizontal overflow. All four app assets loaded; no browser error/warning logs.
- Arrow-key and Home-key screenshot tab changes; correct selected state and panel visibility.
- Native FAQ disclosure exposes screenshot origin and generated-backdrop disclosure.
- Closed signup click reports no email collected; no form submission or network collection enabled.
- JavaScript syntax, unique IDs, fragment/ARIA targets, local assets and whitespace checks pass.
- Impeccable finish review: ship. A displaced skip link in the full-page mobile capture was a stitching artifact; normal viewport capture and offscreen DOM bounds confirm no page defect.

## Remaining activation gate

`landing/config.js` still has an empty `waitlistUrl`. Signup is deliberately closed. User must finish Pulse email/MailerLite account setup and provide an approved HTTPS hosted-form Share URL. Then verify double opt-in, invitation sender, privacy, confirmation and unsubscribe before driving acquisition. No analytics installed in this slice. No deployment or merge performed; user visual/functional approval remains the merge gate.
