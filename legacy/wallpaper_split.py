#!/usr/bin/env python3
"""
wallpaper_split — set the macOS Tahoe (26) Lock Screen wallpaper independently
from the Desktop wallpaper.

Mechanism (reverse-engineered from the "Wallper" app, v1.12.1, macOS 26.6.2):

  macOS 26 stores wallpaper state per display in a binary plist:

    ~/Library/Application Support/com.apple.wallpaper/Store/Index.plist

  Structure (active config lives under the top-level "Displays" dict):

    Displays
      <displayUUID>
        Type            = "individual"          # lock screen and desktop are separate
        Desktop.Content.Choices[0]              # the desktop picture
          Provider      = com.apple.wallpaper.choice.image
          Configuration = <nested binary plist> { type: "imageFile",
                                                  url: { relative: "file:///..." } }
        Idle.Content.Choices[0]                 # the LOCK SCREEN / screen saver
          Provider      = com.apple.wallpaper.choice.image
          Configuration = ...

  The "Idle" project is the *screen saver* (what plays when the Mac is idle and
  which is what shows over the Lock Screen once the screen saver starts). The
  "Desktop" project is the desktop picture. On macOS 26 the Lock Screen itself
  mirrors the desktop, so the way to make the Lock Screen *look* different from
  the desktop is to give it a different screen saver (Idle) - which is exactly
  the "live Lock Screen wallpaper" flow.

  Two important behaviours discovered on macOS 26.6.2:
   * The desktop picture is really driven by the *classic* setting (what
     `NSWorkspace -setDesktopImageURL:` / `System Events` writes), not by the
     store's Desktop project alone.
   * WallpaperAgent reconciles the store across every scope (Displays /
     SystemDefault / Spaces). Editing one display's Idle alone gets reverted, so
     the lock/screen-saver image is written to every Idle project.

  After writing the store we restart WallpaperAgent so it reloads state:

    killall WallpaperAgent

  Keep System Settings closed while applying, or it may overwrite the store.

This tool only edits Index.plist and restarts WallpaperAgent. It never touches
the live Desktop via AppKit, so both projects are set through the same path.

Usage:
  python3 wallpaper_split.py list
  python3 wallpaper_split.py set --lock LOCK.png --desktop DESK.jpg [--all|--display UUID]
  python3 wallpaper_split.py set --lock LOCK.png          # only the lock screen
  python3 wallpaper_split.py restore [--list-backups]

Exit codes: 0 ok, 1 error, 2 usage.
"""

from __future__ import annotations

import argparse
import base64
import datetime as _dt
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse
import uuid
from pathlib import Path

STORE_DIR = Path.home() / "Library/Application Support/com.apple.wallpaper/Store"
INDEX = STORE_DIR / "Index.plist"
BACKUP_DIR = Path.home() / ".wallpaper-split"

AERIALS_DIR = Path.home() / "Library/Application Support/com.apple.wallpaper/aerials"
AERIAL_MANIFEST = AERIALS_DIR / "manifest/entries.json"
AERIAL_VIDEOS = AERIALS_DIR / "videos"

PROVIDER_IMAGE = "com.apple.wallpaper.choice.image"
PROVIDER_AERIAL = "com.apple.wallpaper.choice.aerials"
TYPE_INDIVIDUAL = "individual"
WALLPAPER_AGENT = "WallpaperAgent"

# Where we remember the desired lock-screen choice and install the re-apply agent.
DESIRED = BACKUP_DIR / "desired.json"
AGENT_LABEL = "com.wallpaperfix.reapply"
AGENT_PLIST = Path.home() / "Library/LaunchAgents" / f"{AGENT_LABEL}.plist"

# Stable ids for the custom "Wallpaper Fix" category we add to the aerial manifest.
CUSTOM_CATEGORY_ID = "A1B2C3D4-0001-4000-8000-000000000001"
CUSTOM_SUBCATEGORY_ID = "A1B2C3D4-0002-4000-8000-000000000002"
CUSTOM_CATEGORY_NAME = "WallpaperFix"


# --------------------------------------------------------------------------- #
# store I/O
# --------------------------------------------------------------------------- #
def load_store(path: Path) -> dict:
    with path.open("rb") as fh:
        return plistlib.load(fh)


def save_store(store: dict, path: Path) -> None:
    """Atomically write the store as a binary plist (matching the OS format)."""
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".Index.", suffix=".tmp")
    os.close(fd)
    try:
        with open(tmp, "wb") as fh:
            plistlib.dump(store, fh, fmt=plistlib.FMT_BINARY, sort_keys=False)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def backup(path: Path) -> Path | None:
    if not path.exists():
        return None
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = _dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    dst = BACKUP_DIR / f"Index.{stamp}.plist"
    shutil.copy2(path, dst)
    # convenience pointer to the most recent backup
    latest = BACKUP_DIR / "Index.latest.plist"
    shutil.copy2(path, latest)
    return dst


# --------------------------------------------------------------------------- #
# model helpers
# --------------------------------------------------------------------------- #
def image_configuration(image_path: Path) -> bytes:
    """Nested binary plist the OS stores for an image wallpaper choice."""
    url = "file://" + urllib.parse.quote(str(image_path.resolve()), safe="/")
    cfg = {"type": "imageFile", "url": {"relative": url}}
    return plistlib.dumps(cfg, fmt=plistlib.FMT_BINARY, sort_keys=False)


def decode_configuration(blob) -> dict | None:
    if not isinstance(blob, (bytes, bytearray)) or not blob:
        return None
    try:
        val = plistlib.loads(bytes(blob))
        return val if isinstance(val, dict) else {"_value": val}
    except Exception:
        return None


def choice_provider(project: dict) -> str | None:
    choices = project.get("Content", {}).get("Choices") or []
    if choices and isinstance(choices[0], dict):
        return choices[0].get("Provider")
    return None


def encode_option_template(store: dict) -> bytes:
    """Find an existing image project's EncodedOptionValues to reuse as a template.

    EncodedOptionValues carries placement/colour hints. If we can reuse one that
    was produced for the image provider, the OS accepts it verbatim.
    """
    fallback = None
    for proj in _iter_projects(store):
        eov = proj.get("Content", {}).get("EncodedOptionValues")
        if isinstance(eov, (bytes, bytearray)) and eov:
            if choice_provider(proj) == PROVIDER_IMAGE:
                return bytes(eov)
            fallback = fallback or bytes(eov)
    if fallback is not None:
        return fallback
    # minimal, as seen on aerial projects: {"values": {}}
    return plistlib.dumps({"values": {}}, fmt=plistlib.FMT_BINARY, sort_keys=False)


def _iter_projects(store: dict):
    disp = store.get("Displays")
    if isinstance(disp, dict):
        for entry in disp.values():
            if isinstance(entry, dict):
                for name in ("Desktop", "Idle"):
                    if isinstance(entry.get(name), dict):
                        yield entry[name]
    for root in ("SystemDefault",):
        node = store.get(root)
        if isinstance(node, dict):
            for name in ("Desktop", "Idle"):
                if isinstance(node.get(name), dict):
                    yield node[name]
    spaces = store.get("Spaces")
    if isinstance(spaces, dict):
        for space in spaces.values():
            if not isinstance(space, dict):
                continue
            for disp_entry in space.values():
                if isinstance(disp_entry, dict):
                    for name in ("Desktop", "Idle"):
                        if isinstance(disp_entry.get(name), dict):
                            yield disp_entry[name]


def apply_choice(project: dict, provider: str, config: bytes, eov_template: bytes, now) -> None:
    content = project.setdefault("Content", {})
    content["Choices"] = [{"Provider": provider, "Files": [], "Configuration": config}]
    content["EncodedOptionValues"] = eov_template
    content.setdefault("Shuffle", "$null")
    project["LastSet"] = now
    project["LastUse"] = now


def apply_image(project: dict, image_path: Path, eov_template: bytes, now) -> None:
    apply_choice(project, PROVIDER_IMAGE, image_configuration(image_path), eov_template, now)


def aerial_configuration(asset_id: str) -> bytes:
    return plistlib.dumps({"assetID": asset_id}, fmt=plistlib.FMT_BINARY, sort_keys=False)


# --------------------------------------------------------------------------- #
# commands
# --------------------------------------------------------------------------- #
def describe(store: dict) -> None:
    disp = store.get("Displays", {})
    if not isinstance(disp, dict) or not disp:
        print("No displays found in the store.")
        return
    rows = []
    for uuid, entry in disp.items():
        if not isinstance(entry, dict):
            continue
        last = entry.get("Desktop", {}).get("LastUse")
        rows.append((last, uuid, entry))
    # newest activity first
    rows.sort(key=lambda r: (r[0] or _dt.datetime.min), reverse=True)
    print(f"Store: {INDEX}")
    print(f"{len(rows)} display entries (most recently used first):\n")
    for last, uuid, entry in rows:
        d = entry.get("Desktop", {})
        i = entry.get("Idle", {})
        dcfg = decode_configuration((d.get("Content", {}).get("Choices") or [{}])[0].get("Configuration"))
        icfg = decode_configuration((i.get("Content", {}).get("Choices") or [{}])[0].get("Configuration"))
        print(f"  {uuid}   Type={entry.get('Type')!r}  LastUse={last}")
        print(f"      Desktop     -> {choice_provider(d)}")
        if dcfg:
            print(f"                     {_short(dcfg)}")
        print(f"      Idle(saver) -> {choice_provider(i)}")
        if icfg:
            print(f"                     {_short(icfg)}")
    print()


def _short(cfg: dict) -> str:
    url = cfg.get("url", {})
    if isinstance(url, dict) and "relative" in url:
        return url["relative"]
    if "assetID" in cfg:
        return f"assetID={cfg['assetID']}"
    return str(cfg)[:120]


def cmd_list(args) -> int:
    describe(load_store(INDEX))
    return 0


def _resolve_targets(store: dict, args) -> list[str]:
    disp = store.get("Displays", {})
    if not isinstance(disp, dict):
        print("error: store has no 'Displays' dict", file=sys.stderr)
        return []
    if args.display:
        if args.display not in disp:
            print(f"error: display {args.display!r} not in store", file=sys.stderr)
            return []
        return [args.display]
    return list(disp.keys())


def set_desktop_classic(image: Path) -> None:
    """Set the desktop picture (all spaces/displays) via the classic path.

    On Tahoe the *desktop* picture that AppKit/WallpaperAgent render is driven by
    the classic setting (what `NSWorkspace -setDesktopImageURL:` writes), not by
    the store's Desktop project alone. `System Events` updates that classic
    setting. (This is the desktop half of Wallper's split.)
    """
    script = (
        'tell application "System Events" to set picture of every desktop '
        f'to "{image}"'
    )
    subprocess.run(["/usr/bin/osascript", "-e", script], check=True)


def set_idle_projects(store: dict, provider: str, config: bytes, eov_template: bytes, now) -> int:
    """Set every `Idle` project in the store to the given choice.

    On macOS 26 the `Idle` project is the *screen saver* (what plays once the Mac
    is idle / locked-and-idle), and WallpaperAgent reconciles all scopes
    (Displays / SystemDefault / Spaces). Writing a single display alone gets
    reverted, so we set them all consistently.
    """
    count = 0

    def walk(node):
        nonlocal count
        if isinstance(node, dict):
            for key, val in list(node.items()):
                if key == "Idle" and isinstance(val, dict) and "Content" in val:
                    apply_choice(val, provider, config, eov_template, now)
                    count += 1
                else:
                    walk(val)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(store)
    return count


# --------------------------------------------------------------------------- #
# desired-state tracking + background re-apply agent
# --------------------------------------------------------------------------- #
def save_desired(provider: str, config: bytes) -> None:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    DESIRED.write_text(json.dumps({
        "provider": provider,
        "configuration_b64": base64.b64encode(config).decode("ascii"),
    }))


def load_desired():
    if not DESIRED.exists():
        return None
    d = json.loads(DESIRED.read_text())
    return d["provider"], base64.b64decode(d["configuration_b64"])


def _iter_idle_projects(store: dict):
    def walk(node):
        if isinstance(node, dict):
            for key, val in list(node.items()):
                if key == "Idle" and isinstance(val, dict) and "Content" in val:
                    yield val
                else:
                    yield from walk(val)
        elif isinstance(node, list):
            for item in node:
                yield from walk(item)
    yield from walk(store)


def idle_matches(store: dict, provider: str, config: bytes) -> bool:
    """True if every Idle project already equals the desired choice."""
    found = False
    for proj in _iter_idle_projects(store):
        found = True
        choices = proj.get("Content", {}).get("Choices") or [{}]
        c = choices[0]
        if c.get("Provider") != provider or bytes(c.get("Configuration") or b"") != config:
            return False
    return found


def path_to_url(path: Path) -> str:
    return "file://" + urllib.parse.quote(str(path.resolve()), safe="/")


# --------------------------------------------------------------------------- #
# custom aerial (video) support
# --------------------------------------------------------------------------- #
def encode_hevc(src: Path, dst: Path, max_height: int = 2160) -> None:
    """Transcode a video to HEVC in a .mov container (what the wallpaper service plays)."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    if shutil.which("ffmpeg"):
        subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(src),
                "-vf", f"scale=-2:'min({max_height},ih)'",
                "-c:v", "hevc_videotoolbox", "-tag:v", "hvc1",
                "-pix_fmt", "yuv420p", "-b:v", "12000k", "-an", str(dst),
            ],
            check=True,
        )
    elif shutil.which("avconvert"):
        subprocess.run(
            ["avconvert", "--source", str(src), "--preset", "PresetHEVCHighestQuality",
             "--output", str(dst), "--replace"],
            check=True,
        )
    else:
        raise RuntimeError("need ffmpeg or avconvert to encode HEVC")


def make_preview(mov: Path, dst: Path) -> None:
    if shutil.which("ffmpeg"):
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(mov),
             "-frames:v", "1", "-vf", "scale=640:-2", str(dst)],
            check=True,
        )


def ensure_saver_helper() -> Path:
    """Compile (once) the helper that starts the screen saver via the Dock's
    distributed-notification mechanism (see helper/saver-start.swift)."""
    src = Path(__file__).resolve().with_name("helper") / "saver-start.swift"
    if not src.exists():
        raise RuntimeError(f"helper source missing: {src}")
    bin_dir = BACKUP_DIR / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    exe = bin_dir / "saver-start"
    if (not exe.exists()) or exe.stat().st_mtime < src.stat().st_mtime:
        if not shutil.which("swiftc"):
            raise RuntimeError("swiftc not found (install the Xcode command line tools)")
        subprocess.run(["swiftc", "-O", "-o", str(exe), str(src)], check=True)
    return exe


def register_aerial(video: Path, title: str) -> str:
    """Encode `video`, add it to the aerial manifest, and return its assetID."""
    if not AERIAL_MANIFEST.exists():
        raise RuntimeError(f"aerial manifest not found: {AERIAL_MANIFEST}")

    # back up the manifest before we touch it
    bakdir = BACKUP_DIR / "aerials"
    bakdir.mkdir(parents=True, exist_ok=True)
    stamp = _dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    shutil.copy2(AERIAL_MANIFEST, bakdir / f"entries.{stamp}.json")

    asset_id = str(uuid.uuid4()).upper()
    AERIAL_VIDEOS.mkdir(parents=True, exist_ok=True)
    mov = AERIAL_VIDEOS / f"{asset_id}.mov"
    preview = AERIAL_VIDEOS / f"{asset_id}-preview.png"

    encode_hevc(video, mov)
    make_preview(mov, preview)

    manifest = json.loads(AERIAL_MANIFEST.read_text())
    if not isinstance(manifest.get("assets"), list):
        manifest["assets"] = []

    # ensure our category + subcategory exist
    cats = manifest.setdefault("categories", [])
    cat = next((c for c in cats if c.get("id") == CUSTOM_CATEGORY_ID), None)
    if cat is None:
        cat = {
            "id": CUSTOM_CATEGORY_ID,
            "localizedDescriptionKey": CUSTOM_CATEGORY_NAME + "Description",
            "localizedNameKey": CUSTOM_CATEGORY_NAME,
            "preferredOrder": 0,
            "previewImage": path_to_url(preview),
            "representativeAssetID": asset_id,
            "subcategories": [],
        }
        cats.insert(0, cat)
    if not any(s.get("id") == CUSTOM_SUBCATEGORY_ID for s in cat.get("subcategories", [])):
        cat.setdefault("subcategories", []).insert(0, {
            "id": CUSTOM_SUBCATEGORY_ID,
            "localizedDescriptionKey": CUSTOM_CATEGORY_NAME + "SubDescription",
            "localizedNameKey": CUSTOM_CATEGORY_NAME + "Sub",
            "preferredOrder": -1,
            "previewImage": path_to_url(preview),
            "representativeAssetID": asset_id,
        })

    manifest["assets"] = [a for a in manifest["assets"] if a.get("id") != asset_id]
    manifest["assets"].insert(0, {
        "id": asset_id,
        "url-4K-SDR-240FPS": path_to_url(mov),
        "previewImage": path_to_url(preview),
        "accessibilityLabel": title,
        "localizedNameKey": title,
        "categories": [CUSTOM_CATEGORY_ID],
        "subcategories": [CUSTOM_SUBCATEGORY_ID],
        "preferredOrder": 0,
        "includeInShuffle": False,
        "showInTopLevel": True,
        "pointsOfInterest": {},
        "shotID": title,
    })

    tmp = AERIAL_MANIFEST.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(manifest))
    os.replace(tmp, AERIAL_MANIFEST)
    return asset_id


def cmd_set(args) -> int:
    if not args.lock and not args.desktop:
        print("error: pass --lock and/or --desktop", file=sys.stderr)
        return 2
    for label, p in (("--lock", args.lock), ("--desktop", args.desktop)):
        if p and not Path(p).expanduser().is_file():
            print(f"error: {label} image not found: {p}", file=sys.stderr)
            return 2

    lock = Path(args.lock).expanduser().resolve() if args.lock else None
    desktop = Path(args.desktop).expanduser().resolve() if args.desktop else None

    if lock and desktop and lock == desktop:
        print("note: --lock and --desktop are the same image (they will match).")

    if args.dry_run:
        if desktop:
            print(f"desktop -> {desktop}   (via classic NSWorkspace/System Events path)")
        if lock:
            print(f"lock    -> {lock}   (via Store Idle project + killall WallpaperAgent)")
        print("\n[dry-run] nothing written.")
        return 0

    bak = backup(INDEX)
    if bak:
        print(f"backup: {bak}")

    # 1) lock screen via the Store Idle project, then reload WallpaperAgent.
    #    (Restarting the agent is what makes the Idle project take effect. It also
    #    re-applies the desktop from state, so the desktop is set *afterwards*.)
    if lock:
        store = load_store(INDEX)
        eov = encode_option_template(store)
        now = _dt.datetime.now()
        cfg = image_configuration(lock)
        count = set_idle_projects(store, PROVIDER_IMAGE, cfg, eov, now)
        save_store(store, INDEX)
        save_desired(PROVIDER_IMAGE, cfg)
        print(f"lock    -> {lock}   ({count} Idle/screen-saver projects)")
        print(f"wrote:  {INDEX}")
        if args.no_restart:
            print("WallpaperAgent NOT restarted; run: killall WallpaperAgent")
        else:
            subprocess.run(["/usr/bin/killall", WALLPAPER_AGENT], check=False)
            print(f"restarted: {WALLPAPER_AGENT}")
            time.sleep(1.0)

    # 2) desktop via the classic path, after any restart so it is not clobbered.
    if desktop:
        try:
            set_desktop_classic(desktop)
            print(f"desktop -> {desktop}")
        except subprocess.CalledProcessError as exc:
            print(f"error: could not set desktop via System Events ({exc}); "
                  f"grant Automation permission to your terminal if prompted.",
                  file=sys.stderr)
            return 1

    print("\nNote: keep System Settings closed while applying, or it may overwrite the store.")
    return 0


def cmd_video(args) -> int:
    src = Path(args.video).expanduser()
    if not src.is_file():
        print(f"error: video not found: {src}", file=sys.stderr)
        return 2
    title = args.title or src.stem
    if args.dry_run:
        print(f"would encode {src} -> HEVC aerial {title!r} and set it as the Lock Screen / screen saver")
        return 0

    bak = backup(INDEX)
    if bak:
        print(f"backup: {bak}")
    print("encoding -> HEVC 1080p/4K (can take a while)…")
    asset_id = register_aerial(src, title)
    print(f"registered aerial: {asset_id}")

    store = load_store(INDEX)
    eov = encode_option_template(store)
    now = _dt.datetime.now()
    cfg = aerial_configuration(asset_id)
    count = set_idle_projects(store, PROVIDER_AERIAL, cfg, eov, now)
    save_store(store, INDEX)
    save_desired(PROVIDER_AERIAL, cfg)
    print(f"lock    -> aerial {asset_id}   ({count} Idle/screen-saver projects)")
    print(f"wrote:  {INDEX}")

    if args.no_restart:
        print("WallpaperAgent NOT restarted; run: killall WallpaperAgent")
    else:
        subprocess.run(["/usr/bin/killall", WALLPAPER_AGENT], check=False)
        print(f"restarted: {WALLPAPER_AGENT}")
    print("\nNote: keep System Settings closed while applying, or it may overwrite the store.")
    return 0


def cmd_saver_delay(args) -> int:
    secs = max(0, args.seconds)
    subprocess.run(
        ["/usr/bin/defaults", "-currentHost", "write", "com.apple.screensaver", "idleTime", "-int", str(secs)],
        check=True,
    )
    got = subprocess.run(
        ["/usr/bin/defaults", "-currentHost", "read", "com.apple.screensaver", "idleTime"],
        capture_output=True, text=True,
    )
    print(f"screen saver idleTime = {got.stdout.strip()} s "
          f"(the Lock Screen shows the saver image after this much inactivity)")
    return 0


def cmd_saver_now(args) -> int:
    exe = ensure_saver_helper()
    subprocess.run([str(exe)], check=False)
    print("started the screen saver"
          + ("" if args.no_lock_note else " (locks the Mac if 'Require password after screen saver begins' = immediately)"))
    return 0


def eov_for_provider(store: dict, provider: str) -> bytes:
    """Reuse an existing EncodedOptionValues blob produced for this provider."""
    for proj in _iter_projects(store):
        if choice_provider(proj) == provider:
            eov = proj.get("Content", {}).get("EncodedOptionValues")
            if isinstance(eov, (bytes, bytearray)) and eov:
                return bytes(eov)
    return encode_option_template(store)


def cmd_default_saver(args) -> int:
    """Set the Lock Screen / screen saver to a built-in provider (default: macintosh)."""
    provider = args.provider
    if args.asset_id:
        config = aerial_configuration(args.asset_id)
    else:
        config = b""
    store = load_store(INDEX)
    eov = eov_for_provider(store, provider)
    backup(INDEX)
    n = set_idle_projects(store, provider, config, eov, _dt.datetime.now())
    save_store(store, INDEX)
    save_desired(provider, config)
    print(f"lock    -> {provider}" + (f" assetID={args.asset_id}" if args.asset_id else "")
          + f"   ({n} Idle/screen-saver projects)")
    if not args.no_restart:
        subprocess.run(["/usr/bin/killall", WALLPAPER_AGENT], check=False)
        print(f"restarted: {WALLPAPER_AGENT}")
    return 0


def cmd_reapply(args) -> int:
    """Re-apply the desired lock-screen choice if macOS reverted it (agent entry point)."""
    d = load_desired()
    if not d:
        return 0
    provider, config = d
    store = load_store(INDEX)
    if idle_matches(store, provider, config):
        return 0
    eov = encode_option_template(store)
    n = set_idle_projects(store, provider, config, eov, _dt.datetime.now())
    save_store(store, INDEX)
    subprocess.run(["/usr/bin/killall", WALLPAPER_AGENT], check=False)
    print(f"re-applied lock-screen wallpaper to {n} Idle projects")
    return 0


def cmd_install_agent(args) -> int:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    log = BACKUP_DIR / "reapply.log"
    plist = {
        "Label": AGENT_LABEL,
        "ProgramArguments": [sys.executable, str(Path(__file__).resolve()), "reapply"],
        "RunAtLoad": True,
        "StartInterval": max(30, args.interval),
        "WatchPaths": [str(STORE_DIR)],
        "StandardOutPath": str(log),
        "StandardErrorPath": str(log),
        "ProcessType": "Background",
    }
    AGENT_PLIST.parent.mkdir(parents=True, exist_ok=True)
    with AGENT_PLIST.open("wb") as fh:
        plistlib.dump(plist, fh)
    uid = os.getuid()
    subprocess.run(["launchctl", "bootout", f"gui/{uid}", str(AGENT_PLIST)], check=False)
    subprocess.run(["launchctl", "bootstrap", f"gui/{uid}", str(AGENT_PLIST)], check=False)
    print(f"installed launch agent: {AGENT_PLIST}")
    print(f"  watches {STORE_DIR} and re-applies when macOS reverts it "
          f"(also every {max(30, args.interval)}s)")
    return 0


def cmd_uninstall_agent(args) -> int:
    uid = os.getuid()
    subprocess.run(["launchctl", "bootout", f"gui/{uid}", str(AGENT_PLIST)], check=False)
    if AGENT_PLIST.exists():
        AGENT_PLIST.unlink()
    print("removed launch agent")
    return 0


def cmd_restore(args) -> int:
    if args.list_backups:
        if BACKUP_DIR.exists():
            for p in sorted(BACKUP_DIR.glob("Index.*.plist")):
                print(p)
        return 0
    src = BACKUP_DIR / "Index.latest.plist"
    if not src.exists():
        print(f"error: no backup at {src}", file=sys.stderr)
        return 1
    shutil.copy2(src, INDEX)
    print(f"restored {INDEX} from {src}")
    subprocess.run(["/usr/bin/killall", WALLPAPER_AGENT], check=False)
    print(f"restarted: {WALLPAPER_AGENT}")
    return 0


# --------------------------------------------------------------------------- #
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    lp = sub.add_parser("list", help="show displays and their Desktop / Idle wallpapers")
    lp.set_defaults(func=cmd_list)

    sp = sub.add_parser("set", help="set Lock Screen and/or Desktop wallpaper")
    sp.add_argument("--lock", metavar="IMAGE", help="image to use for the Lock Screen (Idle project)")
    sp.add_argument("--desktop", metavar="IMAGE", help="image to use for the Desktop")
    sp.add_argument("--display", metavar="UUID", help="target one display UUID (default: all)")
    sp.add_argument("--all", action="store_true", help="apply to every display (default)")
    sp.add_argument("--no-restart", action="store_true", help="do not restart WallpaperAgent")
    sp.add_argument("--dry-run", action="store_true", help="show what would change, do not write")
    sp.set_defaults(func=cmd_set)

    vp = sub.add_parser("video", help="set a video as the Lock Screen / screen saver (custom aerial)")
    vp.add_argument("video", metavar="VIDEO", help="source video (any format ffmpeg/avconvert can read)")
    vp.add_argument("--title", help="display name for the aerial (default: file name)")
    vp.add_argument("--no-restart", action="store_true")
    vp.add_argument("--dry-run", action="store_true")
    vp.set_defaults(func=cmd_video)

    dp = sub.add_parser("saver-delay", help="seconds of inactivity before the screen saver starts (0 = never)")
    dp.add_argument("seconds", type=int)
    dp.set_defaults(func=cmd_saver_delay)

    np = sub.add_parser("saver-now", help="start the screen saver now (locks the Mac if so configured)")
    np.add_argument("--no-lock-note", action="store_true", help=argparse.SUPPRESS)
    np.set_defaults(func=cmd_saver_now)

    dsp = sub.add_parser("default-saver", help="set the Lock Screen/saver to a built-in provider (default: macintosh)")
    dsp.add_argument("--provider", default="com.apple.wallpaper.choice.macintosh",
                     help="provider id (default: com.apple.wallpaper.choice.macintosh)")
    dsp.add_argument("--asset-id", help="aerial assetID (only for the aerials provider)")
    dsp.add_argument("--no-restart", action="store_true")
    dsp.set_defaults(func=cmd_default_saver)

    rapr = sub.add_parser("reapply", help="re-apply the desired lock-screen wallpaper if macOS reverted it")
    rapr.set_defaults(func=cmd_reapply)

    iap = sub.add_parser("install-agent", help="install the background re-apply agent (launchd)")
    iap.add_argument("--interval", type=int, default=300,
                     help="fallback check interval in seconds (default 300; min 30)")
    iap.set_defaults(func=cmd_install_agent)

    uap = sub.add_parser("uninstall-agent", help="remove the background re-apply agent")
    uap.set_defaults(func=cmd_uninstall_agent)

    rp = sub.add_parser("restore", help="restore the most recent backup of Index.plist")
    rp.add_argument("--list-backups", action="store_true")
    rp.set_defaults(func=cmd_restore)

    args = ap.parse_args(argv)
    if not INDEX.exists():
        print(f"error: store not found at {INDEX}", file=sys.stderr)
        return 1
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())