> **Beta build** — ad-hoc signed, not notarized. Gatekeeper will warn on first launch.

## Install

1. Download `Pulse-*.dmg`
2. Open DMG → drag **Pulse** to Applications
3. First launch: **right-click Pulse.app → Open** (bypasses Gatekeeper warning)
   - Or in Terminal: `xattr -dr com.apple.quarantine /Applications/Pulse.app`

## Requirements

- macOS 14 (Sonoma) or later

## Known limitations (beta)

- No auto-update yet
- Some TCC permission prompts on first run for storage scanning

## Feedback

Open an issue or ping [@VenkateshDas](https://github.com/VenkateshDas).
