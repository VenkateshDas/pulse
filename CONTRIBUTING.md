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
```

CI runners have a healthy toolchain and invoke SwiftPM directly — no workaround.

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

**Signing:** builds are currently **ad-hoc signed** — Gatekeeper warns on first
launch on other Macs (right-click → Open). To ship a signed + notarized DMG,
add the Apple Developer secrets noted at the top of `release.yml`.
