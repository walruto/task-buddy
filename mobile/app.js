const config = window.TASK_BUDDY_SUPABASE;
const authCard = document.querySelector("#auth-card");
const authForm = document.querySelector("#auth-form");
const passwordResetForm = document.querySelector("#password-reset-form");
const tasksCard = document.querySelector("#tasks-card");
const focusLab = document.querySelector("#focus-lab");
const status = document.querySelector("#status");
const list = document.querySelector("#tasks");
const empty = document.querySelector("#empty");
const buddy = document.querySelector("#buddy");
const buddyMessage = document.querySelector("#buddy-message");
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const focusCorePromise = import("./focus-core.mjs");
let session = JSON.parse(localStorage.getItem("taskBuddySession") || "null");
let buddyTimer;
let idleTimer;
let idleSequenceIndex = 0;
let focusBuddyMode = "";
let taskSocket;
let heartbeatTimer;
let reconnectTimer;
let reconnectAttempts = 0;
let openTasks = [];
let focusStatsByTask = new Map();
let recoveryAccessToken = null;

const frameSet = (state, count) => Array.from({ length: count }, (_, index) => `${state}-${index + 1}.png`);
const buddyStates = {
  idle: frameSet("idle", 6), wave: frameSet("wave", 5), happy: frameSet("happy", 4),
  thinking: frameSet("thinking", 6), error: frameSet("error", 5), locked: frameSet("locked", 4),
  look: frameSet("look", 5), dance: frameSet("dance", 9)
};
const buddyFrameMs = { idle: 110, wave: 120, happy: 115, thinking: 145, error: 150, locked: 125, look: 160, dance: 110 };

const idleSequences = [
  { frames: buddyStates.idle, frameMs: buddyFrameMs.idle, delayMs: 3400 },
  { frames: buddyStates.look.concat("idle-1.png"), frameMs: buddyFrameMs.look, delayMs: 4600 },
  { frames: buddyStates.dance.concat("idle-1.png"), frameMs: buddyFrameMs.dance, delayMs: 6200 }
];

const focusElements = {
  alerts: document.querySelector("#focus-alerts"), back: document.querySelector("#focus-back"),
  camera: document.querySelector("#focus-camera"), cameraEmpty: document.querySelector("#focus-camera-empty"),
  cameraEmptyCopy: document.querySelector("#focus-camera-empty-copy"), cameraEmptyTitle: document.querySelector("#focus-camera-empty-title"),
  cameraFrame: document.querySelector("#focus-camera-frame"), cameraRetry: document.querySelector("#focus-camera-retry"),
  completeSummary: document.querySelector("#focus-complete-summary"), duration: document.querySelector("#focus-duration"),
  elapsed: document.querySelector("#focus-elapsed"), end: document.querySelector("#focus-end"), error: document.querySelector("#focus-error"),
  faceSignal: document.querySelector("#focus-face-signal"), gazeSignal: document.querySelector("#focus-gaze-signal"),
  mode: document.querySelector("#focus-mode"), overlay: document.querySelector("#focus-overlay"), pause: document.querySelector("#focus-pause"),
  percent: document.querySelector("#focus-percent"), postureSignal: document.querySelector("#focus-posture-signal"),
  recalibrate: document.querySelector("#focus-recalibrate"), retrySave: document.querySelector("#focus-retry-save"),
  scan: document.querySelector("#focus-scan"), sensitivity: document.querySelector("#focus-sensitivity"),
  sessionState: document.querySelector("#focus-session-state"), settings: document.querySelector("#focus-settings"),
  start: document.querySelector("#focus-start"), stateBadge: document.querySelector("#focus-state-badge"),
  streak: document.querySelector("#focus-streak"), taskTitle: document.querySelector("#focus-task-title"),
  testSound: document.querySelector("#focus-test-sound"), timeline: document.querySelector("#focus-timeline"),
  timer: document.querySelector("#focus-timer"), timerCaption: document.querySelector("#focus-timer-caption")
};

const MEDIAPIPE_URL = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.1.1/+esm";
const MEDIAPIPE_WASM_URL = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.1.1/wasm";
const FACE_MODEL_URL = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task";
const CALIBRATION_SAMPLES = 30;
const GRACE_SECONDS = { relaxed: 5, balanced: 3, strict: 1.5 };

const focus = {
  task: null, landmarker: null, FaceLandmarker: null, drawing: null, stream: null, audio: null,
  running: false, paused: false, baseline: null, calibration: [], signalWindow: [],
  attention: { focused: true, reason: "Ready", kind: "ready" }, metrics: null,
  plannedSeconds: 25 * 60, remainingSeconds: 25 * 60, startedAt: null, lastDetectionAt: 0,
  animationFrame: 0, interval: 0, inferenceBusy: false, timeline: Array(24).fill("empty"), timelineBucket: -1,
  pendingSummary: null, closeAfterSave: false, historyActive: false
};

for (let index = 0; index < 24; index++) focusElements.timeline.append(document.createElement("span"));

function showStatus(message = "", success = false) {
  status.textContent = message;
  status.style.color = success ? "#8df0bd" : "#ff9fa8";
}

function showBuddy(state, message, duration = 1800) {
  clearInterval(buddyTimer);
  clearTimeout(idleTimer);
  const frames = buddyStates[state] || buddyStates.idle;
  buddyMessage.textContent = message;
  buddy.src = frames[0];
  if (!reduceMotion && frames.length > 1) {
    let frame = 0;
    buddyTimer = setInterval(() => { frame = (frame + 1) % frames.length; buddy.src = frames[frame]; }, buddyFrameMs[state] || 140);
  }
  if (state !== "idle" && duration > 0) idleTimer = setTimeout(startIdle, reduceMotion ? 900 : duration);
}

function startIdle() {
  clearInterval(buddyTimer);
  clearTimeout(idleTimer);
  buddy.src = buddyStates.idle[0];
  if (reduceMotion) return;
  const sequence = idleSequences[idleSequenceIndex % idleSequences.length];
  idleSequenceIndex += 1;
  idleTimer = setTimeout(() => {
    let frame = 0;
    buddy.src = sequence.frames[frame];
    buddyTimer = setInterval(() => {
      frame += 1;
      if (frame >= sequence.frames.length) {
        clearInterval(buddyTimer);
        startIdle();
        return;
      }
      buddy.src = sequence.frames[frame];
    }, sequence.frameMs);
  }, sequence.delayMs);
}

async function request(path, options = {}, retry = true, authenticated = true) {
  const headers = { apikey: config.publishableKey, "Content-Type": "application/json", ...(options.headers || {}) };
  if (authenticated && session?.access_token) headers.Authorization = `Bearer ${session.access_token}`;
  const response = await fetch(`${config.url}/${path}`, { ...options, headers });
  if (response.status === 401 && session?.refresh_token && retry) {
    await refreshSession();
    return request(path, options, false, authenticated);
  }
  const text = await response.text();
  const data = text ? JSON.parse(text) : null;
  if (!response.ok) {
    const error = new Error(data?.message || data?.msg || data?.error_description || "Request failed.");
    error.status = response.status;
    throw error;
  }
  return data;
}

function saveSession(value) {
  session = value;
  value ? localStorage.setItem("taskBuddySession", JSON.stringify(value)) : localStorage.removeItem("taskBuddySession");
  if (!value) stopRealtime();
}

async function refreshSession() {
  try {
    const data = await request("auth/v1/token?grant_type=refresh_token", { method: "POST", body: JSON.stringify({ refresh_token: session.refresh_token }) }, false, false);
    saveSession(data);
  } catch (error) {
    error.authFailure = true;
    throw error;
  }
}

async function authenticate(mode) {
  const email = document.querySelector("#email").value.trim();
  const password = document.querySelector("#password").value;
  const path = mode === "signup" ? "auth/v1/signup" : "auth/v1/token?grant_type=password";
  showBuddy("thinking", "Connecting your quest log...");
  const data = await request(path, { method: "POST", body: JSON.stringify({ email, password }) }, false, false);
  if (!data.access_token) {
    showStatus("Check your email to confirm the account, then sign in.", true);
    showBuddy("wave", "Check your inbox, then come back!");
    return;
  }
  saveSession(data);
  showBuddy("happy", "You're in! Let's get things done.");
  await showTasks();
}

async function resendConfirmation() {
  const emailField = document.querySelector("#email");
  const email = emailField.value.trim();
  if (!emailField.checkValidity()) {
    emailField.reportValidity();
    showStatus("Enter the email you used to create the account.");
    return;
  }
  showBuddy("thinking", "Sending a fresh confirmation link...");
  await request("auth/v1/resend", { method: "POST", body: JSON.stringify({ type: "signup", email }) }, false, false);
  showStatus("Confirmation email sent. Check your inbox and spam folder.", true);
  showBuddy("wave", "Sent! Check your inbox and spam folder.");
}

async function requestPasswordReset() {
  const emailField = document.querySelector("#email");
  const email = emailField.value.trim();
  if (!emailField.checkValidity()) {
    emailField.reportValidity();
    showStatus("Enter the email used for your Task Buddy account.");
    return;
  }
  showBuddy("thinking", "Sending your reset link...");
  await request(
    `auth/v1/recover?redirect_to=${encodeURIComponent("taskbuddy://reset-password")}`,
    { method: "POST", body: JSON.stringify({ email }) },
    false,
    false
  );
  localStorage.setItem("taskBuddyResetEmail", email);
  showStatus("Reset email sent. Open its link on this Android phone.", true);
  showBuddy("wave", "Reset link sent. Check your inbox!");
}

function beginPasswordRecoveryFromURL() {
  const params = new URLSearchParams(location.hash.replace(/^#/, ""));
  const accessToken = params.get("access_token");
  if (params.get("type") !== "recovery" || !accessToken) return false;
  recoveryAccessToken = accessToken;
  authCard.hidden = false;
  tasksCard.hidden = true;
  focusLab.hidden = true;
  authForm.hidden = true;
  passwordResetForm.hidden = false;
  showStatus("Choose a new password below.", true);
  showBuddy("wave", "Let’s make you a new password!");
  history.replaceState(null, "", location.pathname);
  return true;
}

async function completePasswordRecovery() {
  const password = document.querySelector("#new-password").value;
  const confirmation = document.querySelector("#confirm-password").value;
  if (password.length < 8) throw new Error("Use at least 8 characters for the new password.");
  if (password !== confirmation) throw new Error("The new passwords do not match.");
  if (!recoveryAccessToken) throw new Error("Open the newest reset link from your email and try again.");
  await request("auth/v1/user", {
    method: "PUT",
    headers: { Authorization: `Bearer ${recoveryAccessToken}` },
    body: JSON.stringify({ password })
  }, false, false);
  const email = localStorage.getItem("taskBuddyResetEmail");
  recoveryAccessToken = null;
  passwordResetForm.reset();
  passwordResetForm.hidden = true;
  authForm.hidden = false;
  if (email) {
    document.querySelector("#email").value = email;
    document.querySelector("#password").value = password;
    await authenticate("signin");
    localStorage.removeItem("taskBuddyResetEmail");
  } else {
    showStatus("Password changed. Sign in with your new password.", true);
    showBuddy("happy", "Password changed! You’re ready to sign in.");
  }
}

async function loadFocusSessions() {
  const rows = await request("rest/v1/focus_sessions?select=task_id,status,elapsed_seconds,focused_seconds,longest_streak_seconds,alert_count,ended_at&order=ended_at.desc");
  focusStatsByTask = new Map();
  for (const row of rows) {
    const current = focusStatsByTask.get(row.task_id) || { completedSeconds: 0, latest: null };
    if (row.status === "completed") current.completedSeconds += row.elapsed_seconds;
    current.latest ||= row;
    focusStatsByTask.set(row.task_id, current);
  }
  return rows;
}

async function saveFocusSession(summary) {
  return request("rest/v1/focus_sessions", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify(summary) });
}

async function loadTasks() {
  const rows = await request("rest/v1/buddy_tasks?select=id,title,notes,due_date&completed=eq.false&order=due_date.asc.nullslast,created_at.asc");
  openTasks = rows.map(task => {
    try {
      const metadata = JSON.parse(task.notes || "{}");
      return { ...task, due_time: metadata.due_time || null, category: metadata.category || null };
    }
    catch { return task; }
  });
  try {
    await loadFocusSessions();
  } catch (error) {
    focusStatsByTask = new Map();
    showStatus(`Tasks loaded, but focus history could not load: ${error.message}`);
  }
  list.replaceChildren(...openTasks.map(taskRow));
  empty.hidden = openTasks.length > 0;
  if (window.TaskBuddyAndroid) window.TaskBuddyAndroid.syncTasks(JSON.stringify(openTasks));
}

function stopRealtime() {
  clearInterval(heartbeatTimer);
  clearTimeout(reconnectTimer);
  if (taskSocket) { taskSocket.onclose = null; taskSocket.close(); taskSocket = null; }
}

async function startRealtime() {
  if (!session?.access_token || taskSocket?.readyState === WebSocket.OPEN || taskSocket?.readyState === WebSocket.CONNECTING) return;
  if (session.expires_at && session.expires_at * 1000 <= Date.now() + 60000) await refreshSession();
  clearTimeout(reconnectTimer);
  const socketURL = `${config.url.replace("https://", "wss://")}/realtime/v1/websocket?apikey=${encodeURIComponent(config.publishableKey)}&vsn=1.0.0`;
  const socket = new WebSocket(socketURL);
  taskSocket = socket;
  socket.onopen = () => {
    reconnectAttempts = 0;
    socket.send(JSON.stringify({
      topic: "realtime:task-buddy-phone", event: "phx_join",
      payload: { config: { broadcast: { ack: false, self: false }, presence: { enabled: false }, postgres_changes: [
        { event: "INSERT", schema: "public", table: "buddy_tasks" }, { event: "UPDATE", schema: "public", table: "buddy_tasks" }
      ] }, access_token: session.access_token }, ref: "1", join_ref: "1"
    }));
    clearInterval(heartbeatTimer);
    heartbeatTimer = setInterval(() => {
      if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ topic: "phoenix", event: "heartbeat", payload: {}, ref: String(Date.now()) }));
    }, 25000);
  };
  socket.onmessage = event => {
    const message = JSON.parse(event.data);
    if (message.event === "postgres_changes" && focusLab.hidden) loadTasks().catch(error => showStatus(error.message));
    if (message.event === "phx_reply" && message.payload?.status === "error") { if (session) session.expires_at = 0; socket.close(); }
  };
  socket.onclose = () => {
    clearInterval(heartbeatTimer);
    if (taskSocket === socket) taskSocket = null;
    if (session) {
      const delay = Math.min(1000 * (2 ** reconnectAttempts), 10000);
      reconnectAttempts += 1;
      reconnectTimer = setTimeout(() => startRealtime().catch(error => showStatus(error.message)), delay);
    }
  };
}

function taskRow(task) {
  const item = document.createElement("li");
  const actions = document.createElement("div");
  actions.className = "task-actions";
  const complete = document.createElement("button");
  complete.type = "button";
  complete.setAttribute("aria-label", `Complete ${task.title}`);
  complete.textContent = "Done";
  complete.addEventListener("click", async () => {
    try {
      complete.disabled = true;
      await request(`rest/v1/buddy_tasks?id=eq.${encodeURIComponent(task.id)}`, { method: "PATCH", body: JSON.stringify({ completed: true }) });
      showBuddy("happy", "Quest complete. Nice work!");
      await loadTasks();
    } catch (error) {
      complete.disabled = false;
      showStatus(error.message);
      showBuddy("error", "Hmm... that didn't work. Try again?");
    }
  });
  const focusButton = document.createElement("button");
  focusButton.type = "button";
  focusButton.className = "focus-task-button";
  focusButton.setAttribute("aria-label", `Start a focus session for ${task.title}`);
  focusButton.textContent = "Focus";
  focusButton.addEventListener("click", () => openFocusLab(task));
  actions.append(complete, focusButton);

  const copy = document.createElement("div");
  copy.className = "task-copy";
  const title = document.createElement("p");
  title.className = "task-title";
  title.textContent = task.title;
  copy.append(title);
  if (task.due_date) {
    const due = document.createElement("p");
    due.className = "task-due";
    const dueAt = new Date(`${task.due_date}T${task.due_time || "12:00:00"}`);
    const dueTime = task.due_time ? ` · ${dueAt.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}` : "";
    due.textContent = `DUE // ${dueAt.toLocaleDateString()}${dueTime}`;
    copy.append(due);
  }
  if (task.category) {
    const category = document.createElement("span");
    category.className = "task-category";
    category.textContent = task.category;
    copy.append(category);
  }
  const stats = focusStatsByTask.get(task.id);
  if (stats) {
    const focusCopy = document.createElement("p");
    focusCopy.className = "task-focus-stats";
    const latestPercent = stats.latest.elapsed_seconds > 0 ? Math.round(stats.latest.focused_seconds / stats.latest.elapsed_seconds * 100) : 0;
    focusCopy.textContent = `FOCUS // ${Math.round(stats.completedSeconds / 60)} MIN COMPLETE · LATEST ${latestPercent}% · ${stats.latest.alert_count} ALERTS`;
    copy.append(focusCopy);
  }
  item.append(actions, copy);
  return item;
}

async function showTasks() {
  authCard.hidden = true;
  tasksCard.hidden = false;
  showStatus();
  try {
    await loadTasks();
    await startRealtime();
    if (window.TaskBuddyAndroid) window.TaskBuddyAndroid.requestNotificationPermission();
  } catch (error) {
    if (error.status === 401 || error.authFailure) {
      saveSession(null);
      authCard.hidden = false;
      tasksCard.hidden = true;
      showBuddy("error", "Your sign-in expired. Please sign in again.");
    } else {
      startRealtime().catch(() => {});
      showBuddy("error", "You're offline. I'll reconnect automatically.");
    }
    showStatus(error.message);
  }
}

function setFocusState(kind, label) {
  focusElements.stateBadge.className = `focus-state ${kind}`;
  focusElements.stateBadge.textContent = label;
  updateFocusBuddy(kind);
}

function updateFocusBuddy(kind) {
  if (focusLab.hidden || !focus.task) return;
  const mode = kind === "distracted" || kind === "no-face" ? "locked" : kind;
  if (focusBuddyMode === mode) return;
  focusBuddyMode = mode;
  if (mode === "locked") showBuddy("locked", "Hey—lock back in. You’ve got this!", 0);
  else if (mode === "loading" || mode === "calibrating") showBuddy("thinking", "Learning your focus posture...", 0);
  else if (mode === "focused") {
    buddyMessage.textContent = "Locked in. Keep it going!";
    startIdle();
  } else if (mode === "paused") showBuddy("look", "Paused. I’ll wait right here.", 0);
  else if (mode === "completed") showBuddy("happy", "Focus block complete. Nice work!", 2600);
  else if (mode === "error" || mode === "camera-blocked") showBuddy("error", "I can’t watch focus yet. Check the message below.", 0);
  else {
    buddyMessage.textContent = "Choose your setup when you’re ready.";
    startIdle();
  }
}

function setFocusSignal(element, text, className = "") {
  element.textContent = text;
  element.className = className;
}

function updateFocusDuration() {
  if (focus.running) return;
  focus.plannedSeconds = Number(focusElements.duration.value) * 60;
  focus.remainingSeconds = focus.plannedSeconds;
  focusElements.timer.textContent = `${String(Math.floor(focus.remainingSeconds / 60)).padStart(2, "0")}:00`;
  focusElements.timer.dateTime = `PT${focusElements.duration.value}M`;
}

function resetFocusView() {
  focus.pendingSummary = null;
  focus.closeAfterSave = false;
  focusElements.error.hidden = true;
  focusElements.retrySave.hidden = true;
  focusElements.completeSummary.hidden = true;
  focusElements.start.hidden = false;
  focusElements.start.disabled = false;
  focusElements.start.textContent = "Start focus session";
  focusElements.pause.hidden = true;
  focusElements.recalibrate.hidden = true;
  focusElements.end.hidden = true;
  focusElements.settings.querySelectorAll("select").forEach(select => { select.disabled = false; });
  focusElements.sessionState.textContent = "NO SESSION";
  focusElements.timerCaption.textContent = "Choose your setup and begin.";
  focusElements.elapsed.textContent = "00:00";
  focusElements.percent.textContent = "—";
  focusElements.streak.textContent = "00:00";
  focusElements.alerts.textContent = "0";
  focus.timeline = Array(24).fill("empty");
  renderFocusTimeline();
  setFocusState("ready", "Ready");
  updateFocusDuration();
}

function openFocusLab(task, addHistory = true) {
  focus.task = task;
  focusBuddyMode = "";
  focusElements.taskTitle.textContent = task.title;
  tasksCard.hidden = true;
  focusLab.hidden = false;
  resetFocusView();
  showBuddy("wave", `Let's lock in on: ${task.title}`, 2200);
  focusLab.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" });
  if (addHistory) {
    history.pushState({ focusTaskID: task.id }, "", `#focus=${encodeURIComponent(task.id)}`);
    focus.historyActive = true;
  }
}

function leaveFocusLab(fromHistory = false) {
  stopFocusMonitor();
  focusLab.hidden = true;
  tasksCard.hidden = false;
  focus.task = null;
  focusBuddyMode = "";
  focus.historyActive = false;
  showBuddy("wave", "Back to your quest log!", 1600);
  tasksCard.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" });
  if (!fromHistory && location.hash.startsWith("#focus=")) history.back();
}

async function requestLeaveFocus(fromHistory = false) {
  if (focus.running) {
    if (!confirm("End this focus session and return to your quests?")) {
      if (fromHistory) history.pushState({ focusTaskID: focus.task.id }, "", `#focus=${encodeURIComponent(focus.task.id)}`);
      return;
    }
    focus.closeAfterSave = true;
    if (fromHistory) focus.historyActive = false;
    await finishFocusSession("ended");
    return;
  }
  leaveFocusLab(fromHistory);
}

function ensureFocusAudio() {
  const AudioContextClass = window.AudioContext || window.webkitAudioContext;
  if (!AudioContextClass) return false;
  focus.audio ||= new AudioContextClass();
  if (focus.audio.state === "suspended") focus.audio.resume().catch(() => {});
  return true;
}

function playFocusAlert() {
  if (!ensureFocusAudio()) return false;
  const now = focus.audio.currentTime;
  const gain = focus.audio.createGain();
  gain.gain.setValueAtTime(0.0001, now);
  gain.gain.exponentialRampToValueAtTime(0.72, now + 0.025);
  gain.gain.setValueAtTime(0.72, now + 1.02);
  gain.gain.exponentialRampToValueAtTime(0.0001, now + 1.25);
  gain.connect(focus.audio.destination);
  [0, 0.34, 0.68].forEach((offset, index) => {
    const oscillator = focus.audio.createOscillator();
    oscillator.type = "square";
    oscillator.frequency.setValueAtTime([660, 880, 1100][index], now + offset);
    oscillator.connect(gain);
    oscillator.start(now + offset);
    oscillator.stop(now + offset + 0.27);
  });
  return true;
}

async function initializeFocusMonitor() {
  if (focus.running || focusElements.start.disabled) return;
  if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) {
    showFocusError("Camera access requires HTTPS or localhost. Open Task Buddy through its secure app or hosted URL.", "error");
    return;
  }
  focusElements.start.disabled = true;
  focusElements.start.textContent = "Loading camera + model...";
  focusElements.cameraRetry.hidden = true;
  setFocusState("loading", "Loading");
  focusElements.timerCaption.textContent = "Downloading the on-device monitor on first use...";
  let stream;
  try {
    // Audio is optional. A browser without Web Audio must not block the camera or focus session.
    ensureFocusAudio();
    const [core, mediaPipe, cameraStream] = await Promise.all([
      focusCorePromise,
      import(MEDIAPIPE_URL),
      navigator.mediaDevices.getUserMedia({ video: { facingMode: "user", width: { ideal: 960 }, height: { ideal: 720 } }, audio: false })
    ]);
    stream = cameraStream;
    focus.stream = stream;
    focusElements.camera.srcObject = stream;
    await focusElements.camera.play();
    const fileset = await mediaPipe.FilesetResolver.forVisionTasks(MEDIAPIPE_WASM_URL);
    focus.landmarker = await mediaPipe.FaceLandmarker.createFromOptions(fileset, {
      baseOptions: { modelAssetPath: FACE_MODEL_URL, delegate: "GPU" }, runningMode: "VIDEO", numFaces: 1,
      minFaceDetectionConfidence: 0.55, minFacePresenceConfidence: 0.55, minTrackingConfidence: 0.55
    });
    focus.FaceLandmarker = mediaPipe.FaceLandmarker;
    focusElements.overlay.width = focusElements.camera.videoWidth;
    focusElements.overlay.height = focusElements.camera.videoHeight;
    focus.drawing = new mediaPipe.DrawingUtils(focusElements.overlay.getContext("2d"));
    focusElements.cameraFrame.classList.add("active");
    focusElements.cameraEmpty.hidden = true;
    await startFocusSession(core);
  } catch (error) {
    console.error("Focus monitor failed", error);
    stream?.getTracks().forEach(track => track.stop());
    stopFocusMonitor();
    const blocked = error?.name === "NotAllowedError" || error?.name === "PermissionDeniedError";
    showFocusError(blocked
      ? "Camera access was blocked. Allow Camera for Task Buddy in browser or Android settings, then try again."
      : "The camera or face model could not start. Check your connection, then try again.", blocked ? "camera-blocked" : "error");
    focusElements.cameraEmptyTitle.textContent = blocked ? "Camera blocked" : "Monitor unavailable";
    focusElements.cameraEmptyCopy.textContent = blocked ? "Allow camera access in settings, then retry." : "Check your connection and retry the model download.";
    focusElements.cameraEmpty.hidden = false;
    focusElements.cameraRetry.hidden = false;
    focusElements.start.disabled = false;
    focusElements.start.textContent = "Try camera again";
  }
}

function startFocusFromButton() {
  initializeFocusMonitor().catch(error => {
    console.error("Focus start failed", error);
    stopFocusMonitor();
    showFocusError("Focus mode could not start. Check camera access, then try again.");
    focusElements.start.disabled = false;
    focusElements.start.textContent = "Try camera again";
  });
}

function showFocusError(message, kind = "error") {
  focusElements.error.textContent = message;
  focusElements.error.hidden = false;
  setFocusState(kind, kind === "camera-blocked" ? "Camera blocked" : "Error");
}

async function startFocusSession(core) {
  const now = performance.now();
  focus.running = true;
  focus.paused = false;
  focus.plannedSeconds = Number(focusElements.duration.value) * 60;
  focus.remainingSeconds = focus.plannedSeconds;
  focus.startedAt = new Date();
  focus.metrics = core.createMetrics(now);
  focus.timeline = Array(24).fill("empty");
  focus.timelineBucket = -1;
  focus.pendingSummary = null;
  focus.closeAfterSave = false;
  focusElements.error.hidden = true;
  focusElements.retrySave.hidden = true;
  focusElements.completeSummary.hidden = true;
  focusElements.settings.querySelectorAll("select").forEach(select => { select.disabled = true; });
  focusElements.start.hidden = true;
  focusElements.pause.hidden = false;
  focusElements.pause.textContent = "Pause";
  focusElements.recalibrate.hidden = false;
  focusElements.end.hidden = false;
  focusElements.sessionState.textContent = "LIVE";
  focusElements.elapsed.textContent = "00:00";
  focusElements.percent.textContent = "—";
  focusElements.streak.textContent = "00:00";
  focusElements.alerts.textContent = "0";
  renderFocusTimeline();
  beginFocusCalibration();
  cancelAnimationFrame(focus.animationFrame);
  clearInterval(focus.interval);
  focus.interval = setInterval(() => updateFocusSession(performance.now()), 250);
  focus.animationFrame = requestAnimationFrame(focusLoop);
}

function beginFocusCalibration() {
  focus.baseline = null;
  focus.calibration = [];
  focus.signalWindow = [];
  focus.attention = { focused: true, reason: "Calibrating", kind: "calibrating" };
  if (focus.metrics) {
    focus.metrics.badSince = 0;
    focus.metrics.alertedForEpisode = false;
    focus.metrics.lastAt = performance.now();
  }
  setFocusState("calibrating", "Calibrating 0%");
  focusElements.scan.hidden = reduceMotion;
  focusElements.timerCaption.textContent = focusElements.mode.value === "paper" ? "Settle into your writing posture." : "Look naturally at the center of the screen.";
  setFocusSignal(focusElements.faceSignal, "SEARCH");
  setFocusSignal(focusElements.gazeSignal, "LEARN");
  setFocusSignal(focusElements.postureSignal, "HOLD");
}

function drawFocusFace(landmarks, focused) {
  const context = focusElements.overlay.getContext("2d");
  context.clearRect(0, 0, focusElements.overlay.width, focusElements.overlay.height);
  if (!landmarks || !focus.drawing) return;
  focus.drawing.drawConnectors(landmarks, focus.FaceLandmarker.FACE_LANDMARKS_FACE_OVAL, { color: focused ? "#8df0bdc7" : "#ff9fa8c7", lineWidth: 2 });
  focus.drawing.drawConnectors(landmarks, focus.FaceLandmarker.FACE_LANDMARKS_LEFT_EYE, { color: "#72e6ff", lineWidth: 1.5 });
  focus.drawing.drawConnectors(landmarks, focus.FaceLandmarker.FACE_LANDMARKS_RIGHT_EYE, { color: "#72e6ff", lineWidth: 1.5 });
  focus.drawing.drawConnectors(landmarks, focus.FaceLandmarker.FACE_LANDMARKS_LEFT_IRIS, { color: "#f8f5ff", lineWidth: 1.5 });
  focus.drawing.drawConnectors(landmarks, focus.FaceLandmarker.FACE_LANDMARKS_RIGHT_IRIS, { color: "#f8f5ff", lineWidth: 1.5 });
}

async function analyzeFocusFrame(now) {
  if (!focus.landmarker || focusElements.camera.readyState < 2 || now - focus.lastDetectionAt < 90) return;
  focus.lastDetectionAt = now;
  const core = await focusCorePromise;
  const result = focus.landmarker.detectForVideo(focusElements.camera, now);
  const landmarks = result.faceLandmarks?.[0] || null;
  const rawSignals = core.deriveSignals(landmarks);
  if (!focus.baseline) {
    if (core.isValidCalibrationSignal(rawSignals)) {
      focus.calibration.push(rawSignals);
      const progress = Math.min(100, Math.round(focus.calibration.length / CALIBRATION_SAMPLES * 100));
      setFocusState("calibrating", `Calibrating ${progress}%`);
      setFocusSignal(focusElements.faceSignal, "FOUND", "good");
      if (focus.calibration.length >= CALIBRATION_SAMPLES) {
        focus.baseline = core.averageSignals(focus.calibration);
        focus.signalWindow = [];
        focus.metrics.lastAt = now;
        focusElements.scan.hidden = true;
        focusElements.timerCaption.textContent = "Stay with the work.";
        setFocusState("focused", "Focused");
      }
    } else {
      setFocusState("no-face", "No face");
      setFocusSignal(focusElements.faceSignal, "LOST", "bad");
    }
  }
  if (rawSignals) {
    focus.signalWindow.push(rawSignals);
    if (focus.signalWindow.length > 5) focus.signalWindow.shift();
  } else focus.signalWindow = [];
  const signals = focus.signalWindow.length ? core.averageSignals(focus.signalWindow) : null;
  focus.attention = document.hidden
    ? { focused: false, reason: "Left the Task Buddy tab", kind: "tab-hidden" }
    : core.classifyAttention(signals, focus.baseline, focusElements.sensitivity.value, focusElements.mode.value);
  drawFocusFace(landmarks, focus.attention.focused);
  updateFocusSignals(signals, focus.attention);
}

function updateFocusSignals(signals, attention) {
  if (!signals) {
    setFocusSignal(focusElements.faceSignal, "LOST", "bad");
    setFocusSignal(focusElements.gazeSignal, "—");
    setFocusSignal(focusElements.postureSignal, "—");
    return;
  }
  setFocusSignal(focusElements.faceSignal, "FOUND", "good");
  const gaze = focusElements.mode.value === "paper" ? "PAPER OK" : attention.kind === "gaze-away" ? "AWAY" : focus.baseline ? "CENTER" : "LEARN";
  setFocusSignal(focusElements.gazeSignal, gaze, attention.kind === "gaze-away" ? "bad" : "good");
  const postureBad = attention.kind === "head-turned";
  setFocusSignal(focusElements.postureSignal, postureBad ? "TURNED" : "GOOD", postureBad ? "bad" : "good");
}

function renderFocusTimeline() {
  [...focusElements.timeline.children].forEach((bar, index) => { bar.className = focus.timeline[index] === "empty" ? "" : focus.timeline[index]; });
}

function updateFocusTimeline(focused) {
  const bucket = Math.floor(focus.metrics.trackedMs / 5000);
  if (bucket === focus.timelineBucket) {
    if (!focused && focus.timeline.at(-1) === "focused") focus.timeline[focus.timeline.length - 1] = "distracted";
  } else {
    focus.timelineBucket = bucket;
    focus.timeline.push(focused ? "focused" : "distracted");
    focus.timeline.shift();
  }
  renderFocusTimeline();
}

async function updateFocusSession(now) {
  if (!focus.running || focus.paused || !focus.baseline) return;
  const core = await focusCorePromise;
  const result = core.advanceMetrics(focus.metrics, now, focus.attention.focused, GRACE_SECONDS[focusElements.sensitivity.value]);
  focus.metrics = result.metrics;
  focus.remainingSeconds = Math.max(0, focus.plannedSeconds - focus.metrics.trackedMs / 1000);
  if (result.shouldAlert) playFocusAlert();
  if (focus.attention.focused) {
    setFocusState("focused", "Focused");
    focusElements.timerCaption.textContent = "Stay with the work.";
  } else {
    const graceLeft = Math.max(0, GRACE_SECONDS[focusElements.sensitivity.value] - (now - focus.metrics.badSince) / 1000);
    setFocusState(focus.attention.kind === "no-face" ? "no-face" : "distracted", focus.attention.reason);
    focusElements.timerCaption.textContent = graceLeft > 0 ? `Refocus · alert in ${graceLeft.toFixed(1)}s` : "Refocus now.";
  }
  updateFocusTimeline(focus.attention.focused);
  focusElements.timer.textContent = core.formatTime(focus.remainingSeconds);
  focusElements.timer.dateTime = `PT${Math.ceil(focus.remainingSeconds)}S`;
  focusElements.elapsed.textContent = core.formatTime(focus.metrics.trackedMs / 1000);
  focusElements.percent.textContent = `${core.focusPercentage(focus.metrics.focusedMs, focus.metrics.trackedMs)}%`;
  focusElements.streak.textContent = core.formatTime(focus.metrics.currentStreakMs / 1000);
  focusElements.alerts.textContent = String(focus.metrics.alertCount);
  if (focus.remainingSeconds <= 0) await finishFocusSession("completed");
}

function focusLoop(now) {
  if (!focus.running) return;
  if (!focus.paused && !focus.inferenceBusy) {
    focus.inferenceBusy = true;
    analyzeFocusFrame(now).catch(error => {
      console.error("Face inference failed", error);
      showFocusError("Face monitoring stopped unexpectedly. End the session and try again.");
    }).finally(() => { focus.inferenceBusy = false; });
  }
  focus.animationFrame = requestAnimationFrame(focusLoop);
}

async function toggleFocusPause() {
  if (!focus.running || !focus.baseline) return;
  if (!focus.paused) await updateFocusSession(performance.now());
  focus.paused = !focus.paused;
  focus.metrics.lastAt = performance.now();
  focus.metrics.badSince = 0;
  focus.metrics.alertedForEpisode = false;
  focusElements.pause.textContent = focus.paused ? "Resume" : "Pause";
  setFocusState(focus.paused ? "paused" : "focused", focus.paused ? "Paused" : "Focused");
  focusElements.timerCaption.textContent = focus.paused ? "Timer, scoring, and alerts are paused." : "Stay with the work.";
}

async function finishFocusSession(statusValue) {
  if (!focus.running || !focus.task) return;
  const core = await focusCorePromise;
  focus.running = false;
  if (focus.baseline && !focus.paused) {
    const finalMetrics = core.advanceMetrics(
      focus.metrics,
      performance.now(),
      focus.attention.focused,
      GRACE_SECONDS[focusElements.sensitivity.value]
    );
    focus.metrics = finalMetrics.metrics;
    if (finalMetrics.shouldAlert) playFocusAlert();
  }
  cancelAnimationFrame(focus.animationFrame);
  clearInterval(focus.interval);
  focus.animationFrame = 0;
  focus.interval = 0;
  const summary = core.createSessionSummary({
    taskID: focus.task.id, mode: focusElements.mode.value, sensitivity: focusElements.sensitivity.value,
    plannedSeconds: focus.plannedSeconds, metrics: focus.metrics, status: statusValue,
    startedAt: focus.startedAt, endedAt: new Date()
  });
  focus.pendingSummary = summary;
  stopFocusMonitor();
  focusElements.pause.hidden = true;
  focusElements.recalibrate.hidden = true;
  focusElements.end.hidden = true;
  focusElements.start.hidden = false;
  focusElements.start.disabled = false;
  focusElements.start.textContent = "Start another session";
  focusElements.settings.querySelectorAll("select").forEach(select => { select.disabled = false; });
  setFocusState("completed", statusValue === "completed" ? "Completed" : "Ended");
  focusElements.sessionState.textContent = statusValue === "completed" ? "BLOCK COMPLETE" : "SESSION ENDED";
  focusElements.timerCaption.textContent = statusValue === "completed" ? "Focus block complete." : "Session ended early.";
  const score = core.focusPercentage(summary.focused_seconds, summary.elapsed_seconds);
  focusElements.completeSummary.textContent = `${core.formatTime(summary.elapsed_seconds)} elapsed · ${score}% focused · ${core.formatTime(summary.longest_streak_seconds)} longest streak · ${summary.alert_count} alerts`;
  focusElements.completeSummary.hidden = false;
  focusElements.error.hidden = true;
  try {
    await savePendingFocusSummary();
  } catch (error) {
    showFocusError(`Your session finished, but its stats were not saved: ${error.message}`);
    focusElements.retrySave.hidden = false;
  }
}

async function savePendingFocusSummary() {
  if (!focus.pendingSummary) return;
  focusElements.retrySave.disabled = true;
  try {
    await saveFocusSession(focus.pendingSummary);
    focus.pendingSummary = null;
    focusElements.retrySave.hidden = true;
    focusElements.error.hidden = true;
    await loadTasks();
    if (focus.closeAfterSave) leaveFocusLab(!focus.historyActive);
  } finally {
    focusElements.retrySave.disabled = false;
  }
}

function stopFocusMonitor() {
  cancelAnimationFrame(focus.animationFrame);
  clearInterval(focus.interval);
  focus.animationFrame = 0;
  focus.interval = 0;
  focus.inferenceBusy = false;
  focus.stream?.getTracks().forEach(track => track.stop());
  focus.stream = null;
  focusElements.camera.srcObject = null;
  try { focus.landmarker?.close(); } catch (_) {}
  focus.landmarker = null;
  focus.drawing = null;
  focus.FaceLandmarker = null;
  const context = focusElements.overlay.getContext("2d");
  context.clearRect(0, 0, focusElements.overlay.width, focusElements.overlay.height);
  focusElements.cameraFrame.classList.remove("active");
  focusElements.cameraEmpty.hidden = false;
  focusElements.cameraEmptyTitle.textContent = "Camera is off";
  focusElements.cameraEmptyCopy.textContent = "It turns on only for a focus session.";
  focusElements.cameraRetry.hidden = true;
  focusElements.scan.hidden = true;
  setFocusSignal(focusElements.faceSignal, "—");
  setFocusSignal(focusElements.gazeSignal, "—");
  setFocusSignal(focusElements.postureSignal, "—");
}

authForm.addEventListener("submit", async event => {
  event.preventDefault();
  try { await authenticate("signin"); }
  catch (error) { showStatus(error.message); showBuddy("error", "Sign-in failed. Check those details."); }
});
document.querySelector("#forgot-password").addEventListener("click", async () => {
  try { await requestPasswordReset(); }
  catch (error) { showStatus(error.message); showBuddy("error", "I couldn’t send the reset link."); }
});
passwordResetForm.addEventListener("submit", async event => {
  event.preventDefault();
  const button = passwordResetForm.querySelector("button[type=submit]");
  button.disabled = true;
  try { await completePasswordRecovery(); }
  catch (error) { showStatus(error.message); showBuddy("error", "That password reset didn’t work yet."); }
  finally { button.disabled = false; }
});
document.querySelector("#sign-up").addEventListener("click", async () => {
  try { await authenticate("signup"); }
  catch (error) { showStatus(error.message); showBuddy("error", "Account setup hit a snag."); }
});
document.querySelector("#resend-confirmation").addEventListener("click", async event => {
  const button = event.currentTarget;
  button.disabled = true;
  try { await resendConfirmation(); }
  catch (error) {
    const rateLimited = error.message.toLowerCase().includes("rate limit");
    showStatus(rateLimited ? "Email limit reached. Wait about an hour, then try again." : error.message);
    showBuddy("error", rateLimited ? "We need to wait before sending again." : "I couldn't resend that email.");
  } finally { button.disabled = false; }
});
document.querySelector("#task-form").addEventListener("submit", async event => {
  event.preventDefault();
  const title = document.querySelector("#title");
  const dueDate = document.querySelector("#due-date");
  const dueTime = document.querySelector("#due-time");
  const category = document.querySelector("#category");
  try {
    await request("rest/v1/buddy_tasks", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({
      title: title.value.trim(),
      due_date: dueDate.value || null,
      notes: JSON.stringify({
        due_time: dueDate.value ? `${dueTime.value || "09:00"}:00` : null,
        category: category.value
      })
    }) });
    title.value = "";
    dueDate.value = "";
    dueTime.value = "09:00";
    category.value = "Personal";
    showBuddy("happy", "Quest added! I'll keep it safe.");
    await loadTasks();
  } catch (error) { showStatus(error.message); showBuddy("error", "I couldn't save that quest."); }
});
document.querySelector("#sign-out").addEventListener("click", () => {
  stopFocusMonitor();
  saveSession(null);
  if (window.TaskBuddyAndroid) window.TaskBuddyAndroid.syncTasks("[]");
  focusLab.hidden = true;
  tasksCard.hidden = true;
  authCard.hidden = false;
  showStatus("Signed out.", true);
  showBuddy("wave", "See you next time!");
});

focusElements.duration.addEventListener("change", updateFocusDuration);
focusElements.start.addEventListener("click", startFocusFromButton);
focusElements.cameraRetry.addEventListener("click", startFocusFromButton);
focusElements.pause.addEventListener("click", toggleFocusPause);
focusElements.recalibrate.addEventListener("click", () => { if (focus.running && !focus.paused) beginFocusCalibration(); });
focusElements.end.addEventListener("click", () => { if (confirm("End this focus session? The partial session will be saved.")) finishFocusSession("ended"); });
focusElements.testSound.addEventListener("click", () => {
  focusElements.timerCaption.textContent = playFocusAlert()
    ? "Test played. System volume controls loudness."
    : "Sound is unavailable in this browser. Focus monitoring still works.";
});
focusElements.retrySave.addEventListener("click", () => { savePendingFocusSummary().catch(error => showFocusError(`Stats still could not save: ${error.message}`)); });
focusElements.back.addEventListener("click", () => requestLeaveFocus(false));

window.addEventListener("popstate", () => { if (!focusLab.hidden) requestLeaveFocus(true); });
document.addEventListener("visibilitychange", () => {
  if (!focus.running || focus.paused || !focus.baseline) return;
  if (document.hidden) {
    focus.attention = { focused: false, reason: "Left the Task Buddy tab", kind: "tab-hidden" };
    focus.metrics.badSince ||= performance.now();
  } else updateFocusSession(performance.now());
});
window.taskBuddyStopCamera = () => stopFocusMonitor();
window.addEventListener("beforeunload", window.taskBuddyStopCamera);

const isRecoveringPassword = beginPasswordRecoveryFromURL();
if (!config?.url || !config?.publishableKey) {
  showStatus("Task Buddy is not configured yet.");
  showBuddy("error", "I need my sync settings first.");
} else if (isRecoveringPassword) {
  // The recovery form is already visible.
} else if (session) {
  showBuddy("wave", "Welcome back! Loading your quests...");
  showTasks();
} else showBuddy("wave", "Hey! I'm your Task Buddy.", 2400);

if (location.hostname !== "appassets.androidplatform.net" && "serviceWorker" in navigator) navigator.serviceWorker.register("sw.js");
window.taskBuddyResume = () => { if (session && focusLab.hidden) showTasks(); };
