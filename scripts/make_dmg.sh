#!/usr/bin/env bash
#
# Package a built .app into a distributable DMG.
#
# Usage: make_dmg.sh <path-to-Mural.app> <output.dmg> [volume-name]
#
set -euo pipefail

APP="${1:?usage: make_dmg.sh <app> <out.dmg> [volume]}"
OUT="${2:?usage: make_dmg.sh <app> <out.dmg> [volume]}"
VOL="${3:-Mural}"

if [ ! -d "$APP" ]; then
  echo "error: app not found: $APP" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"

hdiutil create \
  -volname "$VOL" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$OUT" >/dev/null

echo "created $OUT"
