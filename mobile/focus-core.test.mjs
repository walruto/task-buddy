import assert from "node:assert/strict";
import {
  advanceMetrics,
  averageSignals,
  classifyAttention,
  createMetrics,
  createSessionSummary,
  focusPercentage,
  formatFocusMinutes,
  formatTime,
  isValidCalibrationSignal
} from "./focus-core.mjs";

const baseline = { yaw: 0, pitch: 0.55, gaze: 0.5, eyeOpen: 0.2, faceSize: 0.35 };

assert.deepEqual(averageSignals([
  { yaw: -0.1, pitch: 0.5, gaze: 0.4, eyeOpen: 0.2, faceSize: 0.3 },
  { yaw: 0.1, pitch: 0.6, gaze: 0.6, eyeOpen: 0.3, faceSize: 0.4 }
]), { yaw: 0, pitch: 0.55, gaze: 0.5, eyeOpen: 0.25, faceSize: 0.35 });

assert.equal(classifyAttention(baseline, baseline).focused, true);
assert.equal(classifyAttention(null, baseline).kind, "no-face");
assert.equal(classifyAttention({ ...baseline, yaw: 0.2 }, baseline).kind, "head-turned");
assert.equal(classifyAttention({ ...baseline, gaze: 0.75 }, baseline).kind, "gaze-away");
assert.equal(classifyAttention({ ...baseline, gaze: 0.9, pitch: 0.85 }, baseline, "balanced", "paper").focused, true);
assert.equal(classifyAttention({ ...baseline, yaw: 0.2 }, baseline, "balanced", "paper").kind, "head-turned");
assert.equal(classifyAttention({ ...baseline, eyeOpen: 0.05 }, baseline).kind, "eyes-closed");
assert.equal(isValidCalibrationSignal(baseline), true);
assert.equal(isValidCalibrationSignal({ ...baseline, faceSize: 0.08 }), false);
assert.equal(formatTime(1500), "25:00");
assert.equal(formatTime(0.2), "00:01");
assert.equal(formatTime(-5), "00:00");
assert.equal(formatFocusMinutes(3000), "50 MIN COMPLETE");
assert.equal(focusPercentage(45, 60), 75);

let metrics = createMetrics(0);
({ metrics } = advanceMetrics(metrics, 1000, true, 3));
assert.equal(metrics.focusedMs, 1000);
let result = advanceMetrics(metrics, 2000, false, 3);
metrics = result.metrics;
assert.equal(result.shouldAlert, false);
result = advanceMetrics(metrics, 5000, false, 3);
metrics = result.metrics;
assert.equal(result.shouldAlert, true);
result = advanceMetrics(metrics, 9000, false, 3);
metrics = result.metrics;
assert.equal(result.shouldAlert, false);
result = advanceMetrics(metrics, 10000, true, 3);
metrics = result.metrics;
result = advanceMetrics(metrics, 14000, false, 3);
assert.equal(result.shouldAlert, true);

const summary = createSessionSummary({
  taskID: "task-1", mode: "screen", sensitivity: "balanced", plannedSeconds: 1500,
  metrics: { ...metrics, trackedMs: 60000, focusedMs: 45000, longestStreakMs: 30000, alertCount: 2 },
  status: "completed", startedAt: new Date("2026-01-01T00:00:00Z"), endedAt: new Date("2026-01-01T00:01:00Z")
});
assert.deepEqual(summary, {
  task_id: "task-1", study_mode: "screen", sensitivity: "balanced", status: "completed",
  planned_seconds: 1500, elapsed_seconds: 60, focused_seconds: 45, longest_streak_seconds: 30,
  alert_count: 2, started_at: "2026-01-01T00:00:00.000Z", ended_at: "2026-01-01T00:01:00.000Z"
});

console.log("focus-core: all checks passed");
