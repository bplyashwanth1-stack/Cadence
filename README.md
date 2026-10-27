# Cadence

Synced lyrics for your Mac's lock screen. While music plays in Spotify or Apple Music and the Mac is
locked, Cadence fills the screen with the song's lyrics: one word at a time, animated as it's sung, over a
backdrop built from the album art.

## Features

- **Word stack** — the word being sung gets a highlighter box that sweeps across it; earlier words stack
  above, the next one waits below, and the whole wall drifts in 3D. Icons appear beside ~120 common words.
- **Lines layout** — classic karaoke lines with 8 word effects (reveal, bounce, bloom, typewriter,
  karaoke fill, wave, pop, fade) and 8 line transitions (zoom, flip, slide, push, drop, blur, scale, fade).
- **Aurora background** — a flowing mesh gradient of album colours with the blurred artwork, vignette and
  film grain. Also: solid album colour, album gradient, custom colour, black.
- **Edge glow** that pulses with the vocals.
- **Clock** and a **now-playing bar** with progress; hover for previous / play-pause / next, click or drag
  the progress bar to seek.
- **Fonts** — 23 bundled display fonts plus every font installed on the Mac, with a preview gallery.
- **Desktop overlay** (off by default) — floating lyrics on the desktop.
- Keeps the display awake while lyrics play on the lock screen.

Lyrics come from [LRCLIB](https://lrclib.net) (free, no account). Most songs have line-level timing; word
timing within a line is estimated from word length. Songs with enhanced LRC get exact word timing.

## Requirements

- macOS 14 or later (Aurora's mesh gradient needs macOS 15; the glass bar needs macOS 26)
- Apple silicon
- Xcode command line tools (`xcode-select --install`)

## Build and install

```sh
./build.sh
```

Compiles `Sources/*.swift`, bundles the fonts, ad-hoc signs the app and installs it to
`~/Applications/Cadence.app`.

On first launch macOS asks to let Cadence control Spotify / Music — allow it, since that's how Cadence
reads the current song and position. Rebuilding changes the ad-hoc signature, so macOS may ask again.

## Using it

- Menu bar 🎤 icon → **Settings…** for everything; changes apply live.
- **Preview Lock Screen (10s)** shows the lock-screen view on the desktop so you can tune it without locking.
  From a terminal: `swift scripts/preview.swift`.
- Lock the Mac (Ctrl+Cmd+Q) with music playing to see it for real. You can type your password or use
  Touch ID as usual while lyrics cover the screen.
- Logs go to `~/Library/Logs/Cadence.log`.

## Project layout

| File | What's in it |
|---|---|
| `Sources/main.swift` | App delegate, windows, menu bar, keep-awake |
| `Sources/Core.swift` | Player polling (AppleScript), LRCLIB + LRC parsing, palette extraction, lock-screen space |
| `Sources/Style.swift` | All settings (`StyleValues`), fonts |
| `Sources/WordStack.swift` | Word stack layout and word icons |
| `Sources/Views.swift` | Lines layout, word effects, transitions, stage, desktop overlay |
| `Sources/Aurora.swift` | Aurora background, pre-blurred backdrop, grain |
| `Sources/Controls.swift` | Now-playing bar, hover controls, scrubbing |
| `Sources/Settings.swift` | Settings window |

## Notes

- Showing windows above the lock screen uses private SkyLight APIs, so this can't ship on the Mac App
  Store and may break in a future macOS release.
- The word stack is inspired by [Verci](https://verci.xyz) and the edge glow by [Lumn](https://trylumn.xyz).
  Give the design its own identity before publishing this publicly.
