#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="$ROOT/dist/Task Buddy.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_DIR/TaskBuddy" "$CONTENTS/MacOS/TaskBuddy"
cp "$ROOT/Config/Info.plist" "$CONTENTS/Info.plist"

RESOURCE_BUNDLE="$(find "$BIN_DIR" -maxdepth 1 -name '*TaskBuddyApp*.bundle' -print -quit)"
if [[ -n "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$CONTENTS/Resources/"
fi

# SwiftPM can retain removed resources in its incremental build bundle.
find "$CONTENTS/Resources" -name 'fetch_gmail_reminders.py' -delete

SPRITE="$ROOT/Sources/TaskBuddyApp/Resources/Character/idle-1.png"
if [[ -f "$SPRITE" ]] && command -v magick >/dev/null; then
  ICONSET="$ROOT/.build/TaskBuddy.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for spec in '16 icon_16x16.png' '32 icon_16x16@2x.png' '32 icon_32x32.png' '64 icon_32x32@2x.png' '128 icon_128x128.png' '256 icon_128x128@2x.png' '256 icon_256x256.png' '512 icon_256x256@2x.png' '512 icon_512x512.png' '1024 icon_512x512@2x.png'; do
    size="${spec%% *}"
    name="${spec#* }"
    magick -size 1024x1024 xc:'#BFF5FF' "$SPRITE" -filter point -resize 760x760 -gravity center -composite -resize "${size}x${size}" "$ICONSET/$name"
  done
  iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/TaskBuddy.icns"
fi

codesign --force --deep --sign - "$APP"
echo "$APP"
