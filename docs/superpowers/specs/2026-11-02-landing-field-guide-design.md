# Pulse landing and Guides: Follow the space

## Approved visual direction

The user selected study F on 2 November 2026, after requesting a broader, more contemporary redesign. The direction uses warm white, forest green, generous system typography and a visible progression from observation to understanding to a considered action.

- Product: help Mac owners understand storage and activity before acting.
- Character: approachable, observant, deliberate.
- World: a native Mac workspace and a readable practical field guide.
- Moments: an upright Home product preview and existing instructional screenshots.
- Signature: numbered steps connecting an overview to its supporting details.

The composition study is `.superpowers/brainstorm/22390-1793609409/content/modern-directions-v2.html` in the original checkout. It illustrates direction, not final functionality. Unslop method by Damir Sokolovsky (@heydamir), CC BY 4.0.

## Scope and constraints

Redesign the landing page, Guides hub and existing storage article. Preserve features, factual qualifications, article sources, existing section order, signup destination, canonical URLs and functional controls. Keep the current capability illustration and fictional product previews. No new articles, invented metrics, native Swift changes, analytics-policy changes or new runtime dependencies.

The product specification HTML referenced by repository instructions is absent from the inspected checkouts. Use PRODUCT.md, DESIGN.md and the wiki's current decisions: explain before acting, retain permission/hardware qualifications, use fictional marketing data, and avoid universal recovery or optimization claims.

## Visual system

Use a warm-white canvas (#FAF9F5), white reading surfaces, a low-saturation green-tinted preview stage (#E7EBDF), primary ink (#172F27), secondary ink (#4B5C4D) and Pulse green (#176B56). Hairlines remain quiet. Verify every text/surface pair, including captions and hover states, against WCAG AA.

Use the existing system sans family, weights 400 and 500 with 600 reserved for emphasis. Desktop hero type scales from 64 to 88px; mobile from 40 to 48px. Body text is 18px, article body 18px with approximately 1.65 line height, and captions/navigation at least 14px. Tight tracking applies only to large headings. Numerals use tabular figures where aligned.

Use a 4px spacing grid. Main content caps at 1280px; desktop gutters are 48px and mobile gutters 24px. Section gaps are 80–96px desktop and 48–64px mobile. Controls have 8px corners; framed previews 16px with 24px padding and appropriately nested inner corners. Primary actions remain forest green with white text.

## Landing page

Use F's asymmetric split hero: left-aligned headline and concise supporting copy; an upright, substantial Home preview on the right. Keep Light/Dark controls, accessible tab behavior, full-size preview links and fictional-data disclosure. Proposed headline: “From ‘what’s going on?’ to ‘now I see.’” Supporting copy names storage, memory and busy apps. Preserve one primary early-access action and one secondary in-page exploration link. The native preview supplies the visual detail; remove the tilted stage and scroll-driven Three.js effect from this surface.

Retain the existing sequence of scenarios, indicators, storage, app features, capabilities, trust, approach, early access, FAQ and guide promotion. Give them a shared typographic rhythm rather than identical card grids. Keep the storage showcase's stronger green treatment as a distinct product moment, with qualified captions. Keep indicator colors meaningful and contained within the product visual. Preserve all eight capabilities and their mobile-readable equivalent.

Restyle the existing guide promotion as F's quiet editorial feature: short introduction, article title and a three-step Check / Explore / Choose sequence derived from the real article. Do not add fake future guides or change the article's actual content to fit the promotion.

## Guides hub

Use the same header, warm canvas, type scale and spacing. Replace the generic oversized introduction with “One question. A way forward.” and a plain explanation that the guides use built-in Mac tools. Bring the existing storage article into the opening composition, using its current screenshot, a clear title, description and read link. Retain one real article rather than filling a grid with placeholders. Show the three-step sequence as a content summary, not interactive controls. Keep the footer and privacy link consistent with the landing page.

## Storage article

Keep the complete checked instructions, screenshots, citations, review date, macOS qualifications, privacy notes and product caveats. Recompose the opening with a readable title, concise answer and a compact three-step route. Use white reading space, hairline dividers and a restrained green accent; reserve tinted blocks for genuine safety/context notes. Avoid nested cards.

At desktop widths, use a 208px sticky table of contents beside a 680–760px reading column. The contents remain an anchor navigation with visible keyboard focus. Distinguish numbered sections, action lists, supporting explanations and sources. Screenshots retain their aspect ratio and full-size links. The article's numbering supplies the signature, without numbering every paragraph.

## Responsive behavior and accessibility

Below 900px, stack hero copy before the preview, move the table of contents into normal flow and use single-column guide features. At narrow widths, reduce heading size, wrap actions and keep text readable without horizontal page overflow. Let wide evidence images open full-size; do not shrink interface text into an unreadable pseudo-dashboard. Collapse navigation into an accessible menu if links cannot fit. Keep skip links, semantic headings, meaningful image descriptions, keyboard tabs/FAQ/menu behavior and reduced-motion support.

Motion is limited to short color/opacity feedback for interaction. No looping effects, parallax, animated layout properties, decorative chart motion or entrance cascades. Use one ease-out curve and approximately 160ms interaction transitions.

## Implementation boundaries

Use the existing static HTML/CSS/JavaScript stack. Shared CSS tokens and components cover header, buttons, section headings, reading blocks and footer; page-specific rules handle hero, hub and article. Keep the existing signup and analytics logic intact. Import only the existing Guides content/assets and necessary navigation from `feat/mac-storage-guide`; review its analytics changes separately rather than automatically bringing them into this redesign. Preserve the capability illustration from its pending branch if absent from the implementation base.

Work begins on `feat/landing-field-guide`, branched from main in an isolated managed worktree, because the original checkout has unrelated changes. Do not alter those changes. Reconcile the two pending content branches explicitly during implementation.

## Validation and delivery

Check desktop (1440px), intermediate (900px) and mobile (390px) layouts, plus keyboard navigation, theme tabs, FAQ, article anchors, image links, menu behavior, signup destination, internal links, metadata and page overflow. Run existing static-page checks through an appropriate Make target if available; use `make` from pulse/ for any required native build/test checks. Do not add a browser framework or implementation-mirroring tests for this visual work.

Review the finished pages against the unslop audit and compare the chosen F study. Keep preview rendering to three review rounds. Update index.md and log.md. Open a PR into main, wait for required CI, and then request the user's visual/functional review. Merge only after explicit user approval.

## Self-review

Scope is limited to the three existing surfaces. Sources and product behavior are preserved; typography, layout and copy presentation can change. The chosen study controls visual direction while this document resolves responsive behavior and article structure. There are no placeholder articles, unverified claims or unresolved design requirements.
