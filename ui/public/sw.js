/* Minimal service worker for OpenClaw Control UI: cache app shell for offline load. */
const CACHE_NAME = "openclaw-control-ui-v1";

function isSameOrigin(url) {
  try {
    return new URL(url).origin === self.location.origin;
  } catch {
    return false;
  }
}

function isShellRequest(request) {
  if (!isSameOrigin(request.url)) {
    return false;
  }
  const u = new URL(request.url);
  const path = u.pathname;
  return (
    request.mode === "navigate" ||
    path.endsWith(".js") ||
    path.endsWith(".css") ||
    path.endsWith(".svg") ||
    path.endsWith(".png") ||
    path.endsWith(".ico") ||
    path.endsWith(".html")
  );
}

self.addEventListener("install", (_event) => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))),
      ),
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") {
    return;
  }
  if (!isShellRequest(event.request)) {
    return;
  }

  event.respondWith(
    caches.open(CACHE_NAME).then((cache) =>
      cache.match(event.request).then((cached) => {
        const fetchPromise = fetch(event.request).then((response) => {
          if (response && response.status === 200 && response.type === "basic") {
            void cache.put(event.request, response.clone());
          }
          return response;
        });
        return cached ?? fetchPromise;
      }),
    ),
  );
});
