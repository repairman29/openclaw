let swRegistered = false;

/**
 * Registers the Control UI service worker for offline app-shell caching.
 * Call once when the app has resolved its base path (e.g. from handleFirstUpdated).
 */
export function registerServiceWorker(basePath: string): void {
  if (swRegistered || typeof navigator === "undefined" || !("serviceWorker" in navigator)) {
    return;
  }
  swRegistered = true;
  const base = basePath.trim() ? (basePath.startsWith("/") ? basePath : `/${basePath}`) : "";
  const swUrl = base ? `${base}/sw.js` : "/sw.js";
  const scope = base ? `${base}/` : "./";
  void navigator.serviceWorker.register(swUrl, { scope }).catch(() => {
    // Registration can fail (e.g. wrong scope, not HTTPS in prod). Fail silently.
  });
}
