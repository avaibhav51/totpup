# Totpup demo and screenshots

## Included media

The README uses a looping GIF because it embeds directly as a repository image. Screenshots and the GIF live in `docs/media`, so relative links work on branches and forks.

| File | Content |
| --- | --- |
| `accounts.png` | Demo account list and live-code layout |
| `upcoming-code.png` | Next-period preview with four seconds remaining |
| `compact-popup.png` | Single-account popup |
| `settings.png` | Inline settings, timing, transparency, and protection |
| `locked.png` | Locked vault view |
| `totpup-demo.gif` | 13-second walkthrough of countdown rollover, popup, settings, and locking |

These are native-view renders using only the public demo secret and sample labels. The animated walkthrough uses a simulated clock and switches between rendered UI states. It is not a screen recording of mouse interaction, a real login, or a Touch ID prompt.

## Regenerate

From the project directory:

```sh
zsh scripts/export-media.sh
```

This builds a separate debug executable and runs `--export-media docs/media`. It does not rebuild or re-sign `dist/Totpup.app`, launch the installed app, read Keychain, write saved preferences, or access the clipboard. No additional Python libraries, video tools, developer signing team, or full Xcode installation are required.

Commit the media with the README and renderer so future UI changes can refresh the screenshots consistently.

## Optional real video recording

For a real interaction video, use macOS Shift–Command–5 to record only Totpup with demo accounts. Suggested 30–45 second sequence:

1. Start on the demo account list and show the countdown.
2. Click a demo code; show its copy confirmation without pasting into another app.
3. Open the menu bar paw and show the popup.
4. Open inline settings; show notch duration and transparency.
5. Hover below the notch and let the panel retract.
6. Lock the vault and finish on the locked view; do not record password entry.

Keep real account labels, enrollment QR images, passwords, other apps, and notifications outside the recording. Do not include an enrolled organization's account in public demo media.

GitHub supports video attachments in issues, pull requests, and other supported text fields. For an inline README video, upload the recording through GitHub's attachment UI and use the resulting attachment URL; a local MP4 link alone is not an image embed. The existing GIF needs no external upload.

Sources: [GitHub relative image links](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax), [GitHub attachments](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files).
