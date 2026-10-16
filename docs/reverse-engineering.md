# wallpaper-fix — separate Lock Screen from Desktop on macOS Tahoe (26)

MVP + reverse-engineering notes for making the macOS 26 Lock Screen look
different from the Desktop, based on decompiling the **Wallper** app
(`/Applications/Wallper.app`, v1.12.1, built with the macOS 26.5 SDK) on
macOS **26.6.2 (build 25G83)**.

## TL;DR of what the decomp showed

Wallper is a native Swift/AppKit app. It does **not** use a private login-time
helper or a public "lock screen wallpaper" API. It drives the macOS 26
wallpaper system directly, split across two paths:

| Target | How it is set | Where it lives |
| --- | --- | --- |
| **Desktop picture** | `NSWorkspace -setDesktopImageURL:forScreen:options:error:` | classic desktop setting |
| **Lock Screen / screen saver** | wallpaper **store** `Idle` project + `killall WallpaperAgent` | `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` |

Evidence in the binary: `setDesktopImageURL:forScreen:options:error:`,
`desktopImageOptionsForScreen:`, `Library/Application Support/com.apple.wallpaper/Store`,
`NSPropertyListSerialization`, `com.apple.wallpaper.choice.aerials`, `/usr/bin/killall`,
`installLockscreen(theme:reason:force:)`, `ScreenSaverHelpers`, `LockscreenSync`,
`LockScreenRepairMonitor`, `LockScreenPresence`, `WallpaperUnlockFix`.

## The macOS 26 wallpaper store

`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` (binary plist):

```
AllSpacesAndDisplays : null
SystemDefault        : { Type, Desktop, Idle }
Spaces.<spaceUUID>   : { Default: { Type, Desktop, Idle, Displays.<uuid>: {...} }, Displays: {...} }
Displays.<displayUUID>
    Type    = "individual"            # lock/saver and desktop are independent
    Desktop = { Content: { Choices: [ { Provider, Configuration, Files } ],
                           EncodedOptionValues, Shuffle }, LastSet, LastUse }
    Idle    = { ...same shape... }
```

* `Provider` examples: `com.apple.wallpaper.choice.image`,
  `com.apple.wallpaper.choice.aerials`, `com.apple.wallpaper.choice.color`,
  `com.apple.wallpaper.choice.macintosh`.
* `Configuration` is a **nested binary plist**:
  * image: `{ type: "imageFile", url: { relative: "file:///..." } }`
  * aerial: `{ assetID: "<uuid>" }` (asset registered in
    `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json`
    with a `.mov` under `.../aerials/videos/`)

### Findings that matter (verified on this machine)

1. **The Lock Screen mirrors the Desktop.** Setting the store `Idle` to a solid
   red image did **not** change the Lock Screen (confirmed by the user locking
   the Mac). The `Idle` project is the **screen saver**, which is what shows
   over the Lock Screen once the screen saver starts.
2. **WallpaperAgent reconciles the store.** The store is a *derived* view. An
   edit to a single display's `Idle` is reverted (within seconds, or on agent
   restart) unless every scope (`Displays`, `SystemDefault`, `Spaces`) is made
   consistent. Writing **all** `Idle` projects makes it stick.
3. **Desktop ≠ store.** Editing the store's `Desktop` project did **not** change
   the rendered desktop; the classic path (System Events / `NSWorkspace`) does.
4. **System Settings must be closed** while applying, or its Wallpaper extension
   rewrites the store.

## The tool

`wallpaper_split.py` (standard library only; uses `ffmpeg` or `avconvert` for video):

```sh
python3 wallpaper_split.py list
python3 wallpaper_split.py set --lock LOCK.png --desktop DESKTOP.png   # still image
python3 wallpaper_split.py set --lock LOCK.png --no-restart
python3 wallpaper_split.py video MYVIDEO.mp4 [--title "My clip"]      # custom video/audio-less aerial
python3 wallpaper_split.py saver-delay 20                             # seconds before the saver starts
python3 wallpaper_split.py saver-now                                  # start the saver now (= lock + custom wallpaper)
python3 wallpaper_split.py reapply                                    # re-apply if macOS reverted it (agent entry point)
python3 wallpaper_split.py install-agent [--interval 300]            # keep it from reverting (launchd)
python3 wallpaper_split.py uninstall-agent
python3 wallpaper_split.py restore [--list-backups]
```

**Re-apply agent.** macOS periodically reverts the store's `Idle` back to the
default, which silently drops the custom lock-screen wallpaper. `install-agent`
installs a `launchd` agent (`~/Library/LaunchAgents/com.wallpaperfix.reapply.plist`)
that watches the store directory and re-applies the desired choice whenever it
changes (and every `--interval` seconds as a fallback). The last `set --lock` /
`video` choice is remembered in `~/.wallpaper-split/desired.json`. Verified: a
forced revert is restored within a few seconds. Log: `~/.wallpaper-split/reapply.log`.

* `--lock` writes the screen-saver image to every `Idle` project, then restarts
  `WallpaperAgent`.
* `--desktop` sets the desktop picture via the classic path (after the restart
  so it is not clobbered).
* `video` transcodes the source to HEVC, copies it to
  `~/Library/Application Support/com.apple.wallpaper/aerials/videos/<uuid>.mov`,
  registers it in the aerial manifest under a custom "WallpaperFix" category, and
  sets the `Idle` project to that aerial.
* `saver-delay` sets `idleTime` in `~/Library/Preferences/ByHost/com.apple.screensaver.*.plist`
  (the "Start Screen Saver when inactive" value).
* Every write backs up `Index.plist` to `~/.wallpaper-split/` and the aerial
  manifest to `~/.wallpaper-split/aerials/`.

Test images/video are in `test/` (`lock-red.png`, `desktop-blue.png`, `sample-hevc.mov`).

## Manual test plan

Baseline on this Mac: Lock Screen = same as Desktop; `Idle` = `macintosh`.

### Test A — the `Idle` project is the screen saver  ✅ PASSED
```sh
python3 wallpaper_split.py set --lock test/lock-red.png
python3 wallpaper_split.py saver-delay 20        # then wait ~25s without input
```
Result: screen saver went red, desktop unchanged.

### Test B — Lock Screen differs from Desktop  ✅ PASSED
Set Desktop = picture A and the screen saver = picture B via System Settings,
lock the Mac, wait for the saver: the Lock Screen showed B while the Desktop
stayed A.

### Test C — custom video as the Lock Screen  ✅ PASSED
```sh
cd ~/Documents/PROJECTS/wallpaper-fix
python3 wallpaper_split.py video test/sample-hevc.mov --title "Test Video"
python3 wallpaper_split.py saver-delay 20
# lock the Mac and wait ~25s -> the colourful test bars play
```
Confirmed working: the aerial service accepts a `file://` URL straight from
`.../aerials/videos/<uuid>.mov`, so **no local HTTP server is required**.

## Why the Lock Screen can't be a separate picture

macOS 26 hard-wires the **lock screen background to the desktop picture**. There
is no separate lock-screen wallpaper slot:

* setting the store `Idle` to a red image did **not** change the lock screen;
* the Wallpaper settings' `LockScreenController` is the **Tahoe lock-screen clock
  styling** (`com.apple.loginwindow` → `ClockFontIdentifier`, `ClockFontWeight`),
  not a wallpaper picker;
* Wallper never touches `loginwindow`/`com.apple.desktop.admin` — its whole
  "lock screen" feature is the store `Idle` (the screen saver).

So the three layers are: **Desktop → Lock Screen (= desktop) → Screen Saver
(= `Idle`, settable)**. The screen saver is the only layer that can look
different, and it plays *over* the lock screen once it starts.

### Getting a "different lock screen" in one action

Because locking alone does **not** start the saver, and starting the saver alone
does not lock, tie them together:

* Set a hot corner to **Start Screen Saver** (System Settings → Desktop & Dock →
  Hot Corners). On this Mac the **top-right** corner is already `Start Screen Saver`.
* Make the saver lock the Mac immediately:
  ```sh
  defaults -currentHost write com.apple.screensaver askForPassword -int 1
  defaults -currentHost write com.apple.screensaver askForPasswordDelay -int 0
  ```
  (or System Settings → Lock Screen → "Require password after screen saver
  begins" = **immediately**).

Now flicking to that corner shows your custom Lock Screen wallpaper/video **and**
locks the Mac in a single move.

#### Starting the saver from a script / shortcut

The Dock starts the saver by posting a distributed notification, recovered from
`-[HotCorners _postScreenSaverNotification:]`:

```
name  = "com.apple.screensaver.action"
info  = { "action": 1 }          # 1 = Start Screen Saver
```

(The Dock's start-saver handler calls `-[HotCorners _postScreenSaverNotification:1]`;
`loginwindow` observes it. It does nothing while the screen is already locked.) `saver-now` wraps this (a tiny Swift helper compiled
on first use) so any script/shortcut can trigger it:

```sh
python3 wallpaper_split.py saver-now
```

#### Rebinding the Lock shortcut (Ctrl+Cmd+Q)

macOS has **no built-in way** to remap or disable `Ctrl+Cmd+Q`, and no built-in
keyboard shortcut for "Start Screen Saver" in Tahoe (it exists only as a hot
corner action). To make `Ctrl+Cmd+Q` start the saver (which locks) instead of
locking directly, use a driver-level remapper such as
[Karabiner-Elements](https://karabiner-elements.pqrs.org). A ready rule is in
`karabiner/ctrl-cmd-q-to-screensaver.json`:

```sh
# run once so the helper binary exists
python3 wallpaper_split.py saver-now      # then dismiss the saver
mkdir -p ~/.config/karabiner/assets/complex_modifications
cp karabiner/ctrl-cmd-q-to-screensaver.json ~/.config/karabiner/assets/complex_modifications/
# Karabiner-Elements → Complex Modifications → Add rule
```

Karabiner consumes the original key, so the built-in lock never fires — the
result is one action that shows the custom Lock Screen wallpaper *and* locks.

## Known gaps / next steps

* **Video transport.** ✅ Works with `file://` URLs — no local server needed.
* **Manifest refresh.** macOS periodically refreshes the aerials manifest
  (`~/Library/Preferences/com.apple.wallpaper.aerial.plist` schedules it), which
  can drop custom entries. Wallper re-applies ("stale Wallper aerial(s) from the
  manifest"); the MVP would add a small re-apply hook.
* **Apply flash.** `killall WallpaperAgent` briefly flashes the wallpaper. The
  supported alternative is the `com.apple.wallpaper.agent` mach service / private
  `Wallpaper.framework` (Wallper ships XPC mach services
  `sandimax.Wallper-spks`, `sandimax.Wallper-spki`).
* **Per-display** lock-screen images are not implemented (all displays share one).