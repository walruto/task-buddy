const pointDistance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const mean = values => values.reduce((total, value) => total + value, 0) / values.length;

function irisRatio(landmarks, irisIndexes, cornerIndexes) {
  const irisX = mean(irisIndexes.map(index => landmarks[index].x));
  const corners = cornerIndexes.map(index => landmarks[index].x);
  return (irisX - Math.min(...corners)) / Math.max(0.001, Math.max(...corners) - Math.min(...corners));
}

function eyeOpenRatio(landmarks, indexes) {
  const [outer, upperOuter, upperInner, inner, lowerInner, lowerOuter] = indexes.map(index => landmarks[index]);
  const width = pointDistance(outer, inner);
  return (pointDistance(upperOuter, lowerOuter) + pointDistance(upperInner, lowerInner)) / Math.max(0.001, width * 2);
}

export function deriveSignals(landmarks) {
  if (!landmarks || landmarks.length < 478) return null;

  const leftEdge = landmarks[234];
  const rightEdge = landmarks[454];
  const eyeLine = mean([landmarks[33].y, landmarks[133].y, landmarks[362].y, landmarks[263].y]);
  const faceWidth = pointDistance(leftEdge, rightEdge);
  const nose = landmarks[1];
  const faceMidX = (leftEdge.x + rightEdge.x) / 2;
  const chinDistance = Math.max(0.001, landmarks[152].y - eyeLine);

  return {
    yaw: (nose.x - faceMidX) / Math.max(0.001, faceWidth),
    pitch: (nose.y - eyeLine) / chinDistance,
    gaze: mean([
      irisRatio(landmarks, [468, 469, 470, 471, 472], [33, 133]),
      irisRatio(landmarks, [473, 474, 475, 476, 477], [362, 263])
    ]),
    eyeOpen: mean([
      eyeOpenRatio(landmarks, [33, 160, 158, 133, 153, 144]),
      eyeOpenRatio(landmarks, [362, 385, 387, 263, 373, 380])
    ]),
    faceSize: faceWidth
  };
}

export function averageSignals(samples) {
  if (!samples.length) return null;
  return Object.fromEntries(Object.keys(samples[0]).map(key => [key, mean(samples.map(sample => sample[key]))]));
}

export function isValidCalibrationSignal(signals) {
  return Boolean(signals && signals.faceSize >= 0.12 && signals.eyeOpen >= 0.08);
}

export function classifyAttention(signals, baseline, sensitivity = "balanced", studyMode = "screen") {
  if (!signals) return { focused: false, reason: "No face detected", kind: "no-face" };
  if (!baseline) return { focused: true, reason: "Calibrating", kind: "calibrating" };

  const limits = {
    relaxed: { yaw: 0.14, pitchUp: 0.2, pitchDown: 0.2, gaze: 0.25, eyeFactor: 0.42 },
    balanced: { yaw: 0.1, pitchUp: 0.15, pitchDown: 0.15, gaze: 0.19, eyeFactor: 0.5 },
    strict: { yaw: 0.075, pitchUp: 0.11, pitchDown: 0.11, gaze: 0.14, eyeFactor: 0.58 }
  }[sensitivity] || { yaw: 0.1, pitchUp: 0.15, pitchDown: 0.15, gaze: 0.19, eyeFactor: 0.5 };

  if (studyMode === "paper") {
    limits.pitchDown = Math.max(limits.pitchDown, 0.38);
    limits.gaze = Infinity;
    limits.eyeFactor = Math.min(limits.eyeFactor, 0.4);
  }

  if (signals.faceSize < 0.12) return { focused: false, reason: "Move closer to the camera", kind: "no-face" };
  if (signals.eyeOpen < Math.max(0.08, baseline.eyeOpen * limits.eyeFactor)) {
    return { focused: false, reason: "Eyes closed", kind: "eyes-closed" };
  }
  if (Math.abs(signals.yaw - baseline.yaw) > limits.yaw) {
    return { focused: false, reason: "Head turned sideways", kind: "head-turned" };
  }
  const pitchDelta = signals.pitch - baseline.pitch;
  if (pitchDelta < -limits.pitchUp || pitchDelta > limits.pitchDown) {
    return { focused: false, reason: "Head turned away", kind: "head-turned" };
  }
  if (Math.abs(signals.gaze - baseline.gaze) > limits.gaze) {
    return { focused: false, reason: "Looking away", kind: "gaze-away" };
  }
  return { focused: true, reason: "Locked in", kind: "focused" };
}

export function createMetrics(now = 0) {
  return {
    lastAt: now,
    trackedMs: 0,
    focusedMs: 0,
    currentStreakMs: 0,
    longestStreakMs: 0,
    badSince: 0,
    alertedForEpisode: false,
    alertCount: 0
  };
}

export function advanceMetrics(metrics, now, focused, graceSeconds) {
  const next = { ...metrics };
  const delta = Math.max(0, now - next.lastAt);
  next.lastAt = now;
  next.trackedMs += delta;

  let shouldAlert = false;
  if (focused) {
    next.focusedMs += delta;
    next.currentStreakMs += delta;
    next.longestStreakMs = Math.max(next.longestStreakMs, next.currentStreakMs);
    next.badSince = 0;
    next.alertedForEpisode = false;
  } else {
    next.currentStreakMs = 0;
    next.badSince ||= now - delta;
    if (!next.alertedForEpisode && now - next.badSince >= graceSeconds * 1000) {
      next.alertedForEpisode = true;
      next.alertCount += 1;
      shouldAlert = true;
    }
  }
  return { metrics: next, shouldAlert };
}

export function createSessionSummary({ taskID, mode, sensitivity, plannedSeconds, metrics, status, startedAt, endedAt }) {
  return {
    task_id: taskID,
    study_mode: mode,
    sensitivity,
    status,
    planned_seconds: Math.round(plannedSeconds),
    elapsed_seconds: Math.round(metrics.trackedMs / 1000),
    focused_seconds: Math.round(metrics.focusedMs / 1000),
    longest_streak_seconds: Math.round(metrics.longestStreakMs / 1000),
    alert_count: metrics.alertCount,
    started_at: startedAt.toISOString(),
    ended_at: endedAt.toISOString()
  };
}

export function focusPercentage(focusedSeconds, elapsedSeconds) {
  return elapsedSeconds > 0 ? Math.round(focusedSeconds / elapsedSeconds * 100) : 0;
}

export function formatTime(totalSeconds) {
  const seconds = Math.max(0, Math.ceil(totalSeconds));
  return `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
}

export function formatFocusMinutes(totalSeconds) {
  if (!totalSeconds) return "NO FOCUS TIME YET";
  const minutes = Math.max(1, Math.round(totalSeconds / 60));
  return `${minutes} MIN COMPLETE`;
}
