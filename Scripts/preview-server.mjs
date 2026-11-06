// Minimal static server for previewing the shared UI without a native host.
// Usage: node Scripts/preview-server.mjs [port]
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(fileURLToPath(new URL(".", import.meta.url)), "..", "cmd", "envbox", "web");
const port = Number(process.argv[2] || 4173);
const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
  ".json": "application/json; charset=utf-8"
};

createServer(async (request, response) => {
  try {
    const path = new URL(request.url, "http://localhost").pathname;
    const relative = path === "/" ? "index.html" : path.replace(/^\/+/, "");
    const file = normalize(join(root, relative));
    if (!file.startsWith(root)) {
      response.writeHead(403).end("forbidden");
      return;
    }
    const body = await readFile(file);
    response.writeHead(200, {
      "Content-Type": types[extname(file)] || "application/octet-stream",
      "Cache-Control": "no-store"
    });
    response.end(body);
  } catch (error) {
    response.writeHead(404).end("not found");
  }
}).listen(port, "127.0.0.1", () => {
  console.log("preview: http://127.0.0.1:" + port + "/?demo=1");
});
