const CACHE = "task-buddy-v8-password-reset";
const FRAME_COUNTS = { idle: 6, wave: 5, happy: 4, thinking: 6, error: 5, locked: 4, look: 5, dance: 9 };
const FRAMES = Object.entries(FRAME_COUNTS).flatMap(([state, count]) =>
  Array.from({ length: count }, (_, index) => `./${state}-${index + 1}.png`)
);
const SHELL = [
  "./index.html", "./styles.css", "./app.js", "./focus-core.mjs", "./config.js", "./manifest.webmanifest", "./icon-256.png",
  ...FRAMES
];
self.addEventListener("install", event => event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL))));
self.addEventListener("activate", event => event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key))))));
self.addEventListener("fetch", event => {
  if (event.request.method !== "GET" || !event.request.url.startsWith(self.registration.scope)) return;
  event.respondWith(caches.match(event.request).then(cached => cached || fetch(event.request)));
});
