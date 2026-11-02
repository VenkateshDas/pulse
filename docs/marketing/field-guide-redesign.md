# Follow the space: landing and Guides redesign

The user selected F and approved the design on 2 November 2026, then explicitly requested the same assets. Implementation is on `feat/landing-field-guide` in the managed landing-field-guide worktree.

## Changes

- Spacing: a shared 4px rhythm, larger section gaps, consistent gutters and reading-column widths.
- Color: warm white, restrained forest green and quiet green-tinted product stages.
- Icons: existing line icons retained; no decorative icon set added.
- Copy: concrete hero description, clear guide entry and shorter section labels; factual instructions, sources and qualifications retained.
- Type: system family, lighter heading weights, larger supporting text and readable captions.
- Layout: upright split hero, editorial Guides feature, sticky desktop article contents and stacked mobile reading layout.
- Details: consistent radii, preserved accessible theme tabs, visible focus and native mobile menu disclosure.
- Visuals: all images reuse existing repository assets byte for byte, including the capability illustration and disposable-sample Finder captures. No generated images or image prompts.
- Motion: removed the landing Three.js scroll effect; interaction feedback stays brief and respects reduced motion.

## Integration boundaries

Existing Guides pages/assets came from `feat/mac-storage-guide`. Its default-on analytics change was deliberately excluded to preserve the design scope and existing opt-in policy. Guides and privacy pages make no analytics requests; privacy copy accurately describes that behavior. The homepage signup URL and analytics consent logic are unchanged. A null guard lets site.js handle shared pages without signup elements.

The existing capability illustration came from `feat/capability-illustration`, retaining its text equivalent and readable mobile list. No native Swift sources changed.

## Verification

`make test` passes: 355 tests in 81 suites.

Static checks pass for all five pages: local assets and links, fragments, one H1, unique titles, descriptions, canonical URLs, article schema and sitemap. Existing analytics privacy/event smoke checks pass. These page checks now run in CI.

Browser checks at 1440px, 900px and 390px show no horizontal document overflow on the homepage, Guides hub or article. The indicator image intentionally scrolls within its container. Light/Dark tab clicks and arrow keys, native mobile menu, article anchors, FAQ expansion and the configured signup destination were verified. The article screenshots remain legible at desktop size and link to their original full-size assets.

Unslop method by Damir Sokolovsky (@heydamir), CC BY 4.0.
