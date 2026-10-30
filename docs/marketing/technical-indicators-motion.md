Focal motion: independent technical indicators read as one overview. A single DOM indicator panel eases from a slight three-dimensional angle into alignment with the page as the section scrolls into view. Three.js CSS3DRenderer controls the existing semantic DOM; it does not render text into canvas or collect any device readings. No particle field, no repeating section reveals, no data animation.
Budget: lazy import near viewport; scroll/resize events coalesced into one requested frame; no recursive frame loop; hidden/offscreen/reduced-motion states stay static. Original DOM layout is the default on failed import, unsupported transforms, print or reduced motion. Small self-hosted tree-shaken Three.js subset; no runtime CDN calls.
Scope: remove two annotated elements; add fictional technical indicator showcase, honest availability note; preserve existing color/type/shape system and signup behavior. Verify desktop/mobile, reduced-motion, missing-module fallback, link/tab behavior, original asset exclusions, CI. No native code changes.

## Delivered

- Removed the two annotated elements: storage’s standalone inspection link and the extra label above Home. Existing image links and discreet fictional-data captions remain.
- Added a semantic, divider-led preview for CPU, memory pressure, GPU, free storage, network download activity and macOS thermal state. All values are authored examples. GPU/temperature availability is explained. Source feature check: `DashboardView.swift` vitals/CPU/thermal/network formatting and native GPU sampler.
- Replaced the earlier generic hero entrance with one optional, scroll-linked Three.js CSS3DRenderer leveling motion. No canvas, WebGL, particles, data animation or continuous frame loop.
- Vendored a pinned, tree-shaken Three.js 0.187.0 subset: 56,451 bytes (~16.6 KB gzip), lazy-loaded near the panel. Original MIT license and exact rebuild instructions accompany it. No runtime CDN or added website toolchain dependency.
- Primary content stays semantic/selectable HTML. Reduced motion, failed module loading, unsupported 3D transforms, print and detected zoom changes retain the normal-flow static panel. Hidden/offscreen states do not render; offscreen resizing tears down optional transforms until the section is near again.

## Verification

- Desktop 1440px, mobile 390px, narrow 320px: loaded images, no horizontal overflow. Secondary reading labels are at least 12px.
- Browser DOM confirms both annotated elements absent; screenshot Light/Dark keyboard changes still work. All six readings remain available to accessibility.
- Actual PageDown changed the panel’s Three.js matrix from a slight angle to level. Values remained unchanged.
- Local fixture exercised reduced-motion branch without modifying Mac settings: static initially, renderer after preference toggle, static/original inline style restored after toggling back.
- Local missing-module fixture retained all six readings. Local beforeprint/afterprint fixture verified original DOM restoration and renderer resumption; explicit printing state prevents premature restart.
- 320px offscreen resize returned to static layout without overflow. Normal-flow layout remains the base if JavaScript does not run.
- JS syntax, HTML IDs/ARIA/local assets, whitespace checks pass. Impeccable review: ship; typography/print corrections scored resolved. Documenter preserved the native system files.

Three.js documents CSS3DRenderer’s normal-zoom limitation. The runtime reverts to static after detected pixel-ratio or visual-viewport scale changes; initial nondefault browser/display zoom was not separately exercised. Sources: https://threejs.org/docs/pages/CSS3DRenderer.html and https://registry.npmjs.org/three/0.187.0.

No native app code, analytics, signup activation, deployment or merge. Required macOS CI runs on PR #94; user visual approval remains the merge gate.
