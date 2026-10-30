# Pulse marketing previews — current state 2026-10-30

The earlier real-data capture approach is superseded. User requested fictional data after noticing that screenshots expose their Mac’s information.

## Current implementation

- Home stays in the hero, with Light/Dark previews beside stronger copy.
- Separate forest-green storage stage enlarges the Files columns and explains folder sizes, drill-down and judgment before removal.
- Home, Files, App activity and removal-review previews are static SVG interface replicas based on Pulse’s development UI. All apps, folders, sizes and readings are fictional. They are not native app screenshots; visible captions and FAQ say so.
- `landing/scripts/render-demos.py` renders all five assets deterministically using Python’s standard library. It does not inspect the host Mac, import screenshots, sample system APIs or read user directories.
- Example storage totals: 512 GB total, 448 GB used, 64 GB free. Root and nested fictional folder totals agree. Sample app identities use `com.example`.
- Existing image-generated studio backdrop frames Home; no application content is AI-generated or copied from the owner’s machine.
- Earlier Home, activity and removal screenshots plus their sidecars are removed from the current shipped tree. The temporary local preview snapshot also removes their files; old asset URLs return HTTP 404. Storage’s real capture was never committed.

Historical limit: previous commit `585f4b8` on PR #94 contains the earlier real captures. This change removes them from the current page and assets; it does not purge Git objects, old commit URLs or remote caches.

## Verification

Browser checks at 1440px, 390px and 320px: no horizontal overflow. All five demo assets load. Keyboard Light/Dark switch and the fictional-data FAQ work. Browser warning/error logs empty. HTML IDs/ARIA/fragment links, local asset paths, XML parsing, original-capture 404 responses, JavaScript syntax, raster provenance and whitespace checks pass.

Independent design reviewer scored proportional bars and all icon cleanup resolved (ship at fix scope); documenter confirmed no native-system documentation change required.

No native code changed, no new service or frontend dependency. Signup remains closed pending the user’s approved MailerLite URL and real confirmation/unsubscribe-flow validation. No analytics, deployment or merge enabled by this work. User visual approval remains the merge gate.
