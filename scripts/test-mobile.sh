#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
node --check "$ROOT/mobile/app.js"
node --check "$ROOT/mobile/focus-core.mjs"
node "$ROOT/mobile/focus-core.test.mjs"

for spec in idle:6 wave:5 happy:4 thinking:6 error:5 locked:4 look:5 dance:9; do
  state="${spec%%:*}"
  count="${spec##*:}"
  for frame in $(seq 1 "$count"); do
    test -f "$ROOT/mobile/$state-$frame.png"
  done
done

grep -q 'prefers-reduced-motion' "$ROOT/mobile/styles.css"
grep -q 'id="buddy-message"' "$ROOT/mobile/index.html"
grep -q 'id="resend-confirmation"' "$ROOT/mobile/index.html"
grep -q 'auth/v1/resend' "$ROOT/mobile/app.js"
grep -q 'realtime/v1/websocket' "$ROOT/mobile/app.js"
grep -q 'TaskBuddyAndroid.syncTasks' "$ROOT/mobile/app.js"
grep -q 'id="due-time"' "$ROOT/mobile/index.html"
grep -q 'id="category"' "$ROOT/mobile/index.html"
grep -q 'due_time' "$ROOT/mobile/app.js"
grep -q 'Start a focus session' "$ROOT/mobile/app.js"
grep -q 'id="focus-lab"' "$ROOT/mobile/index.html"
grep -q 'Camera frames stay on this device' "$ROOT/mobile/index.html"
grep -q '@mediapipe/tasks-vision@1.1.1' "$ROOT/mobile/app.js"
grep -q 'focus_sessions' "$ROOT/mobile/app.js"
grep -q 'focus-core.mjs' "$ROOT/mobile/sw.js"
grep -q 'task-buddy-v8-password-reset' "$ROOT/mobile/sw.js"
grep -q 'id="forgot-password"' "$ROOT/mobile/index.html"
grep -q 'id="password-reset-form"' "$ROOT/mobile/index.html"
grep -q 'auth/v1/recover' "$ROOT/mobile/app.js"
grep -q 'taskbuddy://reset-password' "$ROOT/mobile/app.js"
grep -q 'function startFocusFromButton' "$ROOT/mobile/app.js"
grep -q 'Audio is optional' "$ROOT/mobile/app.js"
grep -q 'locked: 125' "$ROOT/mobile/app.js"
grep -q 'kind === "distracted" || kind === "no-face" ? "locked"' "$ROOT/mobile/app.js"
! grep -q 'buddy-pop' "$ROOT/mobile/styles.css"
echo "Mobile animation, focus logic, integration, and accessibility checks passed."
