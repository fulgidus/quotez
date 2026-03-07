import { Database } from "bun:sqlite";
import { getQuote } from "./src/lib/qotd-client";
import path from "node:path";
import fs from "node:fs";

const QOTD_API_HOST = process.env.QOTD_API_HOST ?? "127.0.0.1";
const QOTD_API_PORT = parseInt(process.env.QOTD_API_PORT ?? "8080");
const QOTD_TCP_HOST = process.env.QOTD_TCP_HOST ?? "127.0.0.1";
const QOTD_TCP_PORT = parseInt(process.env.QOTD_TCP_PORT ?? "17");
const QOTD_API_USERNAME = process.env.QOTD_API_USERNAME ?? "admin";
const QOTD_API_PASSWORD = process.env.QOTD_API_PASSWORD ?? "quotez";
const PORT = parseInt(process.env.PORT ?? "3000");
const DB_PATH = process.env.DB_PATH ?? path.join(import.meta.dir, "data", "settings.db");

const dbDir = path.dirname(DB_PATH);
if (!fs.existsSync(dbDir)) {
  fs.mkdirSync(dbDir, { recursive: true });
}
const db = new Database(DB_PATH, { create: true });
console.log(`[server] SQLite database opened at ${DB_PATH}`);

const distDir = path.join(import.meta.dir, "dist");

function serviceUnavailable(): Response {
  return new Response(JSON.stringify({ error: "Service unavailable" }), {
    status: 503,
    headers: { "Content-Type": "application/json" },
  });
}

async function serveStatic(pathname: string): Promise<Response> {
  // Normalise path to prevent directory traversal
  const safePath = path.normalize(pathname).replace(/^(\.\.[/\\])+/, "");
  const filePath = path.join(distDir, safePath === "/" ? "index.html" : safePath);

  const file = Bun.file(filePath);
  if (await file.exists()) {
    return new Response(file);
  }

  const indexFile = Bun.file(path.join(distDir, "index.html"));
  if (await indexFile.exists()) {
    return new Response(indexFile, { headers: { "Content-Type": "text/html" } });
  }

  return new Response(
    `<!DOCTYPE html><html><head><meta charset="utf-8"><title>quotez</title></head>` +
      `<body><h1>quotez</h1><p>UI not built. Run <code>bun run build</code> inside <code>website/</code>.</p></body></html>`,
    { status: 200, headers: { "Content-Type": "text/html" } }
  );
}

async function proxyToZig(req: Request, pathname: string, search: string): Promise<Response> {
  const zigUrl = `http://${QOTD_API_HOST}:${QOTD_API_PORT}${pathname}${search}`;
  const authHeader = "Basic " + btoa(`${QOTD_API_USERNAME}:${QOTD_API_PASSWORD}`);

  const headers: Record<string, string> = {};
  for (const [key, value] of req.headers.entries()) {
    // Strip hop-by-hop headers that should not be forwarded
    const lower = key.toLowerCase();
    if (lower === "host" || lower === "connection" || lower === "keep-alive") continue;
    headers[key] = value;
  }
  headers["Authorization"] = authHeader;

  try {
    const upstream = await fetch(zigUrl, {
      method: req.method,
      headers,
      body: req.method !== "GET" && req.method !== "HEAD" ? req.body : undefined,
    });

    const respHeaders = new Headers();
    for (const [key, value] of upstream.headers.entries()) {
      const lower = key.toLowerCase();
      // Strip hop-by-hop headers that should not be forwarded
      if (lower === "connection" || lower === "keep-alive" || lower === "transfer-encoding") continue;
      respHeaders.set(key, value);
    }

    return new Response(upstream.body, {
      status: upstream.status,
      headers: respHeaders,
    });
  } catch (err) {
    console.error(`[server] Proxy error → ${zigUrl}:`, err);
    return serviceUnavailable();
  }
}

const server = Bun.serve({
  port: PORT,

  async fetch(req) {
    const url = new URL(req.url);
    const { pathname, search } = url;

    if (pathname === "/qotd") {
      try {
        const quote = await getQuote(QOTD_TCP_HOST, QOTD_TCP_PORT);
        return new Response(quote, {
          headers: { "Content-Type": "text/plain; charset=utf-8" },
        });
      } catch (err) {
        console.error("[server] QOTD TCP error:", err);
        return serviceUnavailable();
      }
    }

    if (pathname.startsWith("/api/")) {
      return proxyToZig(req, pathname, search);
    }

    return serveStatic(pathname);
  },

  error(err) {
    console.error("[server] Unhandled error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  },
});

console.log(`[server] Listening on http://localhost:${server.port}`);
console.log(`[server] Zig API proxy → http://${QOTD_API_HOST}:${QOTD_API_PORT}`);
console.log(`[server] QOTD TCP      → ${QOTD_TCP_HOST}:${QOTD_TCP_PORT}`);
