# Mural

**Your Lock Screen, your wallpaper.** Mural gives macOS 26 (Tahoe) a Lock Screen
wallpaper that's different from your desktop — your own photo or video, separate
from the desktop picture.

[![CI](https://github.com/da-the-dev/mural/actions/workflows/ci.yml/badge.svg)](https://github.com/da-the-dev/mural/actions/workflows/ci.yml)
[![Release](https://github.com/da-the-dev/mural/actions/workflows/release.yml/badge.svg)](https://github.com/da-the-dev/mural/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Features

- **Live or still Lock Screen wallpaper** — set a video (transcoded to HEVC) or a
  photo as the screen saver that plays over the Lock Screen.
- **Independent from the desktop** — the desktop picture is untouched.
- **Built-in wallpaper browser** — pick from Apple's aerials or the Macintosh
  default.
- **One-key lock** — `⌃⌘Q` (or the in-app *Lock now*) shows your wallpaper *and*
  locks the Mac.
- **Stays put** — a tiny background agent re-applies your choice when macOS
  resets the wallpaper store.
- Native SwiftUI with **Liquid Glass**.

> **Why the screen saver?** On macOS 26 the Lock Screen background is hard-wired
> to the desktop picture; the *screen saver* is the only layer you can make
> different, and it's what shows over the Lock Screen once it starts. Mural sets
> that layer for you.

## Requirements

- **macOS 26 (Tahoe) or later.**
- Apple silicon.

## Install

1. Download the latest `Mural-x.y.z.dmg` from
   [Releases](https://github.com/da-the-dev/mural/releases).
2. Open it and drag **Mural** to *Applications*.
3. Launch it, pick your Lock Screen wallpaper, and turn on
   **Require password when the screen saver starts** in Settings.

If the DMG isn't notarized yet (no Developer ID configured), macOS may warn about
an unidentified developer: right-click the app → **Open**, or allow it under
System Settings → Privacy & Security.

## Build from source

```sh
brew install xcodegen
xcodegen generate
open Mural.xcodeproj        # then Run
```

From the command line:

```sh
xcodebuild -project Mural.xcodeproj -scheme Mural \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/dd build
./scripts/make_dmg.sh build/dd/Build/Products/Release/Mural.app build/Mural.dmg
```

## Architecture

```
Sources/
  WallpaperKit/   Core logic (no UI): the wallpaper store, aerial catalog,
                  screen-saver control, HEVC transcoding, the re-apply agent.
  Mural/          The SwiftUI app (Liquid Glass UI) + MenuBarExtra.
```

- **`WallpaperStore`** reads/writes
  `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`, setting
  the `Idle` project (the screen saver) while leaving the desktop alone.
- **`ScreenSaver.start()`** posts the system's own start-saver notification.
- **`AerialCatalog`** registers your videos as custom aerials in the aerial
  manifest.
- **`MuralReapply`** (run by a per-user `LaunchAgent`) re-applies the desired
  wallpaper when macOS reverts it — invoke with `Mural --reapply`.

The reverse-engineering notes and the original prototype live in
[`docs/`](docs/) and [`legacy/`](legacy/).

## Releasing

Tag a version and push:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The [release workflow](.github/workflows/release.yml) builds, packages a DMG, and
publishes a GitHub Release. **Signing and notarization turn on automatically** when
these repo secrets are present (otherwise it ships an unsigned DMG):

| Secret | Purpose |
| --- | --- |
| `MACOS_CERTIFICATE` | base64 of your **Developer ID Application** `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | password for that `.p12` |
| `MACOS_SIGNING_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `KEYCHAIN_PASSWORD` | any password for the temporary CI keychain |
| `APPLE_ID` | your Apple ID (for notarization) |
| `APPLE_APP_PASSWORD` | an app-specific password for that Apple ID |
| `APPLE_TEAM_ID` | your 10-character Team ID |

See [`docs/releasing.md`](docs/releasing.md) for how to obtain these.

## Credits

The macOS 26 wallpaper internals (store layout, the `com.apple.screensaver.action`
notification, the aerial manifest schema) were reverse-engineered; see
[`docs/reverse-engineering.md`](docs/reverse-engineering.md). Not affiliated with
Apple. "Apple", "macOS", and "Tahoe" are trademarks of Apple Inc.

## License

[MIT](LICENSE) © 2026 Aleksey Tkachenko
