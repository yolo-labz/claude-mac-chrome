#!/usr/bin/env node
// Tiny static file server for Playwright fixtures. Serves tests/fixtures/
// over http://127.0.0.1:8080/ so Chromium loads them as real http:// URLs
// (not file://), enabling realistic origin + CSP behavior.

import { createServer } from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE_DIR = resolve(__dirname, "..", "fixtures");
const PORT = 8080;

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".json": "application/json",
  ".css": "text/css",
  ".js": "application/javascript",
};

const server = createServer((req, res) => {
  let path = req.url.split("?")[0];
  if (path === "/") path = "/01-plain-upgrade-button.html";
  const filePath = join(FIXTURE_DIR, path.replace(/^\//, ""));
  if (!filePath.startsWith(FIXTURE_DIR) || !existsSync(filePath)) {
    res.writeHead(404);
    res.end("not found");
    return;
  }
  const ext = "." + filePath.split(".").pop();
  res.writeHead(200, { "content-type": TYPES[ext] || "text/plain" });
  res.end(readFileSync(filePath));
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`fixture server listening on http://127.0.0.1:${PORT}`);
});
