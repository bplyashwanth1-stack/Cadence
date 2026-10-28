# Cadence

Synced lyrics for your Mac's lock screen, styled like a lyric edit. While music plays in Spotify or Apple Music
and the Mac is locked, Cadence fills the screen with the song's lyrics, animated word by word as they're sung,
over a moving wallpaper made from the album art that hits on the beat.

## Features

**Lyrics**
- **17 word animations** — comet, neon, glitch, slam, scramble, cascade, flip, highlighter, shine, reveal,
  bounce, bloom, typewriter, karaoke fill, wave, pop, fade — or **Mix**, a different one every line with the
  punchy ones saved for the chorus.
- **Two layouts** — a word stack (one word at a time, drifting in 3D) or classic lines with 8 line transitions.
- **Keyword bursts** — sung words set off effects: "fire" throws up embers, "rain" brings a storm, "love"
  floats hearts, plus stars, lightning, money and snow. Works for Hindi and Telugu words too.
- **Title card** — a new song's title slams in like a music video's opening.
- **Hindi/Telugu in English letters**, spelled the way people type them ("premapichchi", not "premapicci").

**Backgrounds**
- **Album art, moving** — motion wallpaper, floating cover, duotone, spinning vinyl, kaleidoscope, or a
  spinning disc ringed by a live spectrum.
- **Auto** cuts between them like an editor: on the drop, on new sections, every few beats in the chorus.
- **Hears the music** (Core Audio process tap): zooms, flashes and particles kick on the real beat.
- **The artist stands in front of the clock** — the person is cut out of the art with Vision.
- Particles (bokeh, stars, embers, dust), light leaks, RGB split, edge glow, and a backing for readability.

**Presets** — nine looks in one click (Reel Edit, Night Drive, Hype, Chill, Love Letter, Glitchcore, Movie
Subs, Galaxy, Highlighter), plus your own. Switch from the menu bar, or with ✨ on the lock screen itself.

**Getting the lyrics right**
- Lyrics come from [LRCLIB](https://lrclib.net) (free, no account). Uploads are user-submitted, so Cadence
  picks the one whose timing agrees with the rest.
- **Auto-fix timing** — lines up when singing starts in the audio with when lines start, and shifts the
  lyrics when they're clearly early or late.
- **Lyrics repair** — when the timed upload is missing lines or mangled, Cadence rebuilds it from the
  complete untimed lyrics, borrowing the timestamps.
- **Your fixes stick** — nudge a song's timing (menu bar → This Song's Timing) and Cadence remembers it for
  that song. For a truly broken one, **Tap to Sync**: play it once, press Space as each line starts, and
  your timing is used from then on.
- Songs without timed lyrics get a visual mode: the title over a live spectrum.

**Also** — clock, now-playing bar with controls and scrubbing, battery saver (lighter visuals when unplugged),
keeps the display awake while lyrics play, optional floating lyrics on the desktop, 21 bundled fonts plus every
font on the Mac.

## Requirements

- macOS 14 or later (hearing the music needs 14.2, mesh gradients macOS 15, the glass bar macOS 26)
- Apple silicon
- Xcode command line tools (`xcode-select --install`)

## Build and install

```sh
./build.sh
```

Compiles `Sources/*.swift`, bundles the fonts, signs the app and installs it to `~/Applications/Cadence.app`.

On first launch macOS asks to let Cadence control Spotify / Music — that's how it reads the current song and
position — and to record system audio, which it analyses on the Mac for the beat and timing (nothing is
recorded or sent anywhere). `build.sh` signs every build with a local self-signed certificate, created on the
first build by `scripts/signing-identity.sh` in its own keychain, so macOS remembers these permissions across
rebuilds.

## Using it

- Menu bar 🎤 → **Presets**, **Lyric Animation**, **Background**, **Layout**, or **Settings…** for everything.
- **Preview Lock Screen (10s)** shows the lock-screen view on the desktop. From a terminal:
  `swift scripts/preview.swift`.
- Lock the Mac (Ctrl+Cmd+Q) with music playing. Hover the bottom bar for playback controls and ✨ to change
  preset. You can type your password or use Touch ID as usual.
- Logs go to `~/Library/Logs/Cadence.log`.

## Project layout

| File | What's in it |
|---|---|
| `Sources/main.swift` | App delegate, windows, menu bar, keep-awake |
| `Sources/Core.swift` | Player polling (AppleScript), LRCLIB + LRC parsing, palette, now-playing state, lock-screen space |
| `Sources/LyricsRepair.swift` | Rebuilding broken timed lyrics from the untimed ones |
| `Sources/AutoSync.swift` | Auto-fixing lyric timing from the audio; battery detection |
| `Sources/Timing.swift` | Per-song timing nudges and tap-to-sync |
| `Sources/Audio.swift` | Core Audio tap: loudness, bass hits, spectrum, vocal band |
| `Sources/Style.swift` | All settings (`StyleValues`), fonts, romanization |
| `Sources/Presets.swift` | Built-in and saved presets, preset picker and toast |
| `Sources/Director.swift` | When Auto cuts scenes; title card; no-lyrics view |
| `Sources/Views.swift` | Word effects, lines layout, transitions, stage layers, desktop overlay |
| `Sources/WordStack.swift` | Word stack layout and word icons |
| `Sources/Wallpaper.swift` | Artwork backgrounds, spectrum ring, particles, light leaks, lyrics backing |
| `Sources/Bursts.swift` | Keyword bursts |
| `Sources/Aurora.swift` | Aurora background; artwork processing (blur, duotone, subject cut-out); grain |
| `Sources/Controls.swift` | Now-playing bar, hover controls, scrubbing |
| `Sources/Settings.swift` | Settings window |

## Notes

- Showing windows above the lock screen uses private SkyLight APIs, so this can't ship on the Mac App Store and
  may break in a future macOS release.
- The highlighter-box word stack was inspired by [Verci](https://verci.xyz) and the edge glow by
  [Lumn](https://trylumn.xyz).
- Bundled fonts are under the SIL Open Font License; see `Fonts/README.md` and `Fonts/licenses/`.

## License

MIT — see [LICENSE](LICENSE). Bundled fonts keep their own licenses.
