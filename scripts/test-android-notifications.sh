#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

javac -d "$OUT" \
  "$ROOT/android/app/src/main/java/com/taskbuddy/phone/ReminderTime.java" \
  "$ROOT/Tests/Android/ReminderTimeTest.java"
java -ea -cp "$OUT" com.taskbuddy.phone.ReminderTimeTest

grep -q 'android.permission.CAMERA' "$ROOT/android/app/src/main/AndroidManifest.xml"
grep -q 'android.hardware.camera" android:required="false"' "$ROOT/android/app/src/main/AndroidManifest.xml"
grep -q 'WebChromeClient' "$ROOT/android/app/src/main/java/com/taskbuddy/phone/MainActivity.java"
grep -q 'RESOURCE_VIDEO_CAPTURE' "$ROOT/android/app/src/main/java/com/taskbuddy/phone/MainActivity.java"
grep -q 'path.endsWith(".mjs")' "$ROOT/android/app/src/main/java/com/taskbuddy/phone/MainActivity.java"
