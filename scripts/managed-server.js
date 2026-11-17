#!/usr/bin/env node
// LaunchAgent entry point. The same Node process hosts the proxy and bounds its logs.
import fs from "node:fs";
import path from "node:path";

const directory = process.env.CCP_MANAGED_LOG_DIR;
if (!directory) throw new Error("CCP_MANAGED_LOG_DIR is required");
fs.mkdirSync(directory, { recursive: true, mode: 0o700 });

function writer(name) {
  const file = path.join(directory, name);
  const maxBytes = 5 * 1024 * 1024;
  return (...items) => {
    let line = items.map((item) => item instanceof Error ? item.message : String(item)).join(" ").slice(0, 4096);
    line = line.replace(/(windsurf_api_key|CCP_API_KEY|authorization|api[_-]?key)\s*[:=]\s*[^\s,]+/gi, "$1=[REDACTED]")
      .replace(/Bearer\s+\S+/gi, "Bearer [REDACTED]");
    try {
      if (fs.existsSync(file) && fs.statSync(file).size > maxBytes) fs.truncateSync(file, 0);
      fs.appendFileSync(file, `${new Date().toISOString()} ${line}\n`, { mode: 0o600 });
    } catch { /* Logging must never crash the proxy. */ }
  };
}
console.log = writer("runtime.log");
console.error = writer("error.log");
console.warn = console.error;

await import("../src/server.js");
