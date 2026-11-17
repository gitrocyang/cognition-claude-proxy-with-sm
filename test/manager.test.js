import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync, spawn } from "node:child_process";
import net from "node:net";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const wrapper = path.join(root, "bin/dclaude");

test("dclaude does not revive a stopped managed service", () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "dclaude-managed-"));
  const agents = path.join(home, "Library", "LaunchAgents");
  fs.mkdirSync(agents, { recursive: true });
  fs.writeFileSync(path.join(agents, "com.gitrocyang.devin-proxy-manager.proxy.plist"), "managed");
  try {
    const result = spawnSync(wrapper, [], {
      env: { ...process.env, HOME: home, CCP_PORT: "49199", TAVILY_API_KEY: "test" },
      encoding: "utf8", timeout: 5000,
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /managed proxy is stopped/);
  } finally { fs.rmSync(home, { recursive: true, force: true }); }
});

test("dclaude keeps legacy CLI path when no manager agent is installed", () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "dclaude-legacy-"));
  const stub = path.join(home, "bin");
  fs.mkdirSync(stub);
  fs.writeFileSync(path.join(stub, "curl"), "#!/bin/sh\nexit 0\n", { mode: 0o755 });
  fs.writeFileSync(path.join(stub, "claude"), "#!/bin/sh\nprintf 'stub claude: %s\\n' \"$*\"\n", { mode: 0o755 });
  try {
    const result = spawnSync(wrapper, ["-p", "two  spaces"], {
      env: { ...process.env, HOME: home, PATH: `${stub}:${process.env.PATH}`, CCP_PORT: "49198", TAVILY_API_KEY: "test" },
      encoding: "utf8", timeout: 5000,
    });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /stub claude:/);
    assert.match(result.stdout, /two  spaces/);
  } finally { fs.rmSync(home, { recursive: true, force: true }); }
});

test("managed Node entry serves health and writes bounded logs without credentials", async () => {
  const log = fs.mkdtempSync(path.join(os.tmpdir(), "ccp-managed-log-"));
  const probe = net.createServer();
  await new Promise(resolve => probe.listen(0, "127.0.0.1", resolve));
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  const child = spawn(process.execPath, [path.join(root, "scripts/managed-server.js")], {
    cwd: root,
    env: { ...process.env, CCP_PORT: String(port), CCP_MANAGED_LOG_DIR: log, CCP_DEBUG: "" },
    stdio: "ignore",
  });
  try {
    let response;
    for (let i = 0; i < 40; i++) {
      try { response = await fetch(`http://127.0.0.1:${port}/health`); break; }
      catch { await new Promise(resolve => setTimeout(resolve, 100)); }
    }
    assert.equal(response?.status, 200);
    assert.equal((await response.json()).ok, true);
    const runtime = fs.readFileSync(path.join(log, "runtime.log"), "utf8");
    assert.match(runtime, /listening on http:\/\/127\.0\.0\.1/);
    assert.doesNotMatch(runtime, /windsurf_api_key\s*=/);
  } finally {
    child.kill("SIGTERM");
    if (child.exitCode === null) await new Promise(resolve => child.once("exit", resolve));
    fs.rmSync(log, { recursive: true, force: true });
  }
});
