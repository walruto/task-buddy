#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ASSETS="$ROOT/android/app/src/main/assets"
CONFIG="$ROOT/mobile/config.js"

if [ ! -f "$CONFIG" ]; then
  echo "Missing mobile/config.js. Create it from mobile/config.example.js first." >&2
  exit 1
fi

mkdir -p "$ASSETS" "$ROOT/dist"
find "$ASSETS" -maxdepth 1 -type f \( -name 'idle-*.png' -o -name 'wave-*.png' -o -name 'happy-*.png' \
  -o -name 'thinking-*.png' -o -name 'error-*.png' -o -name 'locked-*.png' \
  -o -name 'look-*.png' -o -name 'dance-*.png' \) -delete
cp "$ROOT/mobile/index.html" "$ROOT/mobile/styles.css" "$ROOT/mobile/app.js" "$ROOT/mobile/focus-core.mjs" \
  "$CONFIG" "$ROOT/mobile/icon-256.png" "$ROOT/mobile/manifest.webmanifest" \
  "$ROOT/mobile/sw.js" "$ASSETS/"
for state in idle wave happy thinking error locked look dance; do
  cp "$ROOT/mobile/$state-"*.png "$ASSETS/"
done
cp "$ROOT/mobile/icon-256.png" "$ROOT/android/app/src/main/res/drawable/task_buddy_icon.png"

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"

cd "$ROOT/android"
./gradlew --no-daemon assembleDebug
cp "$ROOT/android/app/build/outputs/apk/debug/app-debug.apk" "$ROOT/dist/TaskBuddy-Android.apk"
echo "$ROOT/dist/TaskBuddy-Android.apk"
