> **Beta build** — ad-hoc signed, not notarized. macOS blocks it on first launch. Universal (Apple Silicon + Intel).

## What's new in v0.2.0-beta.1

Two big additions turn Pulse into a full Mac command center:

- **Menu bar manager** — hide menu bar clutter behind a chevron, with optional
  auto-collapse on a timer. Click to reveal, click to tuck away. Uses standard
  AppKit: no Accessibility permission, no private APIs, no extra helper app.
- **Display brightness control** — per-display brightness over DDC/CI, including
  external monitors. Your physical Brightness Up/Down keys route to whichever
  display the cursor is on, and a software dimming overlay goes darker than the
  panel allows for displays without hardware control.

## Install

1. Download `Pulse-*.dmg`
2. Open DMG → drag **Pulse** to Applications → **eject the DMG**
3. First launch (macOS blocks an un-notarized app). Two ways through:

   **Terminal (reliable on all versions, incl. macOS Sequoia 15):**
   ```sh
   xattr -cr /Applications/Pulse.app
   open /Applications/Pulse.app
   ```

   **Or System Settings:** double-click Pulse → **Done** → **System Settings →
   Privacy & Security → Security → Open Anyway** → authenticate.

   > macOS **Sequoia (15)** removed the old "right-click → Open" bypass — use
   > one of the two methods above. Run `xattr` on the `/Applications` copy, not
   > the one inside the mounted DMG.

## Requirements

- macOS 14 (Sonoma) or later (universal: Apple Silicon + Intel)

## Known limitations (beta)

- No auto-update yet
- Some TCC permission prompts on first run for storage scanning

## Feedback

Open an issue or ping [@VenkateshDas](https://github.com/VenkateshDas).
