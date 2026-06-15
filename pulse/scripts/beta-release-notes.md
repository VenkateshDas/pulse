> **Beta build** — ad-hoc signed, not notarized. macOS blocks it on first launch. Universal (Apple Silicon + Intel).

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
