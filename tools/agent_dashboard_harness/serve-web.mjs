import http from "node:http";
import fs from "node:fs/promises";
import path from "node:path";

const PORT = Number(process.env.RUSTDESK_DASHBOARD_WEB_PORT || "53231");
const ROOT = process.env.RUSTDESK_DASHBOARD_WEB_ROOT
  ? path.resolve(process.env.RUSTDESK_DASHBOARD_WEB_ROOT)
  : path.resolve("build", "web");

const MIME = new Map([
  [".html", "text/html; charset=utf-8"],
  [".js", "application/javascript; charset=utf-8"],
  [".mjs", "application/javascript; charset=utf-8"],
  [".css", "text/css; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".png", "image/png"],
  [".jpg", "image/jpeg"],
  [".jpeg", "image/jpeg"],
  [".svg", "image/svg+xml"],
  [".wasm", "application/wasm"],
  [".ico", "image/x-icon"],
  [".txt", "text/plain; charset=utf-8"],
  [".map", "application/json; charset=utf-8"],
]);

const NO_STORE_HEADERS = {
  "Cache-Control": "no-store, no-cache, max-age=0, must-revalidate",
  "Pragma": "no-cache",
  "Expires": "0",
};

const DEV_SERVICE_WORKER = `
'use strict';
self.addEventListener('install', (event) => {
  self.skipWaiting();
});
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    if (self.caches) {
      const keys = await self.caches.keys();
      await Promise.all(keys.map((key) => self.caches.delete(key)));
    }
    await self.clients.claim();
  })());
});
`;

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://${req.headers.host || "127.0.0.1"}`);
    let relativePath = decodeURIComponent(url.pathname);
    if (relativePath === "/") {
      relativePath = "/index.html";
    }
    const requested = path.normalize(path.join(ROOT, relativePath));
    const safePath = requested.startsWith(ROOT) ? requested : path.join(ROOT, "index.html");
    let filePath = safePath;
    try {
      const stat = await fs.stat(filePath);
      if (stat.isDirectory()) {
        filePath = path.join(filePath, "index.html");
      }
    } catch {
      filePath = path.join(ROOT, "index.html");
    }
    if (path.basename(filePath) === "flutter_service_worker.js") {
      res.writeHead(200, {
        "Content-Type": MIME.get(".js"),
        ...NO_STORE_HEADERS,
      });
      res.end(DEV_SERVICE_WORKER);
      return;
    }
    const bytes = await fs.readFile(filePath);
    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, {
      "Content-Type": MIME.get(ext) || "application/octet-stream",
      ...NO_STORE_HEADERS,
    });
    res.end(bytes);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    res.writeHead(500, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(message);
  }
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`[dashboard-web] serving ${ROOT} on http://127.0.0.1:${PORT}`);
});
