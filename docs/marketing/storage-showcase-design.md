# Home hero + storage showcase — 2026-10-30

User selected: keep Home in the hero, add a dramatic storage section. Implementation proceeds on existing PR #94; no extra design approval round needed.

- Hero: stronger split composition with large, concise copy beside the Home interface demo, visible in the first desktop viewport. Keep the Light/Dark demo switch and early-access CTA.
- Storage: separate full-width forest-green stage with the Files interface demo browsing Demo Disk → Library → Application Support. An enlarged crop makes the three columns readable. Three labeled steps explain compare, follow and review; a full-size preview link preserves context. All folder names and sizes are fictional; do not claim recoverable space.
- Presentation: reuse Pulse greens and cool surfaces, native system type and existing image-generated studio material. One restrained hero entrance; no looping movement. Reduce Motion shows a static composition. Mobile stacks content and exposes full-size images.
- Scope: landing HTML/CSS, deterministic SVG UI replicas + generator, marketing notes and wiki. No native app logic, cleanup action, new service, analytics or signup activation.
- Verification: browser desktop/mobile/narrow widths, image loading, keyboard Light/Dark, full-size preview links, FAQ, closed signup; then independent finish review, docs, PR update and required CI. User approval remains merge gate.

Plan: render fictional UI demos; reshape hero; add storage stage with demo image crop and explanatory steps; check render/behavior; fix review findings; document and push. No new dependency or JS abstraction needed.

User correction: real data must never appear in current landing assets. UI replicas follow Pulse’s anatomy, use fictional fixtures, and are disclosed as replicas rather than native captures. Prior real captures are removed from the current tree and local server; historical Git commits are not purged.
