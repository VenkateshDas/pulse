# Contributing to Pulse

## Branching model

- **`main`** — always releasable. Protected. No direct pushes.
- **`release/*`** — release stabilization branches (e.g. `release/v0.1.0-beta.1`). Protected.
- **feature / fix branches** — branch off `main`, named `feat/...`, `fix/...`, `ci/...`, `docs/...`.

Every change reaches a protected branch through a **pull request that passes CI**.
Branch protection is enforced for everyone, including admins — there is no
direct-push escape hatch by design.

## Workflow

```bash
git checkout main && git pull
git checkout -b fix/short-description
# ... make changes ...
cd pulse && make test          # build + tests, must pass
git push -u origin fix/short-description
gh pr create --fill
```

A PR is mergeable when the **CI / Build & Test (macOS)** check is green.

## Local build

The dev machine has Command Line Tools only (no Xcode) and a broken CLT 26.5
install, so local builds go through `make`, which applies a toolchain
workaround. See `pulse/Makefile`.

```bash
cd pulse
make build      # debug build
make test       # build + run tests
make run        # launch the app
make bundle     # release build wrapped in dist/Pulse.app (ad-hoc signed)
make dev-cert   # one-time: stable local signing (see below)
```

CI runners have a healthy toolchain and invoke SwiftPM directly — no workaround.

### Testing permission-gated features locally

The App Uninstaller needs Full Disk Access / App Management grants. Ad-hoc
builds get a new code hash on every `make bundle`, which makes macOS silently
drop those grants (the app still *shows* as toggled on in Settings). Run
`make dev-cert` **once** to create a stable self-signed identity — `make bundle`
then signs with it and grants persist across rebuilds. To trash an
App Store / root-owned bundle, Pulse asks Finder via in-process Apple Events, so
the first uninstall prompts for "control Finder" and an admin password, like a
manual drag-to-Trash. If a grant ever looks stuck, reset it:
`tccutil reset SystemPolicyAllFiles com.pulse.app` (and `SystemPolicyAppBundles`).

## CI

`.github/workflows/ci.yml` runs on every PR and on pushes to protected
branches: debug build, tests, and a release-build + bundle smoke test (the path
CD relies on).

## Releases (CD)

Releases are tag-driven (`.github/workflows/release.yml`):

```bash
# from an up-to-date main (or release/*), after the release PR is merged:
git tag v0.1.0            # or a pre-release: v0.1.0-beta.2
git push origin v0.1.0
```

CD builds the DMG and publishes a GitHub Release with it attached. Tags ending
in a `-suffix` (e.g. `-beta.1`) are marked as pre-releases.

**Signing:** with no secrets configured, builds are **ad-hoc signed** —
Gatekeeper warns on first launch on other Macs (right-click → Open, or
`xattr -dr com.apple.quarantine /Applications/Pulse.app`). Ad-hoc apps may be
**blocked outright** on MDM-managed machines (e.g. work laptops) whose
Gatekeeper policy only allows identified developers — there is no user-side
bypass for that; the DMG must be notarized.

### Shipping a signed + notarized DMG (required for work/MDM laptops)

The pipeline signs + notarizes automatically once these repo secrets exist
(Settings → Secrets and variables → Actions). No workflow edit needed.

1. **Apple Developer account** ($99/yr) → in *Certificates, IDs & Profiles*
   create a **Developer ID Application** certificate, then export it from
   Keychain Access as a `.p12` (set an export password).
2. Add the **signing** secrets:
   - `APPLE_DEV_ID_CERT_P12_BASE64` — `base64 -i cert.p12 | pbcopy`
   - `APPLE_DEV_ID_CERT_PASSWORD` — the `.p12` export password
   - `APPLE_DEV_ID_IDENTITY` — `Developer ID Application: Your Name (TEAMID)`
3. Add the **notarization** secrets (App Store Connect):
   - `APPLE_ID` — your Apple ID email
   - `APPLE_APP_PASSWORD` — an app-specific password from appleid.apple.com
   - `APPLE_TEAM_ID` — your 10-character Team ID
4. Re-tag (`git tag v0.1.0-beta.5 && git push origin v0.1.0-beta.5`). The
   release job imports the cert into a temporary keychain, signs with the
   hardened runtime, notarizes, and staples — the resulting DMG opens with no
   Gatekeeper warning.

With **only** the signing secrets (step 2) the DMG is signed but not
notarized, so Gatekeeper still warns. Both sets are needed for a clean launch.
Even notarized, a strict MDM allowlist may still require IT to approve the
bundle ID `com.pulse.app` — that's an org policy step, not a build step.

To sign/notarize **locally** instead of via CD:
`make sign SIGN_IDENTITY="Developer ID Application: …"` then
`make notarize NOTARY_PROFILE=<stored notarytool profile>`.
