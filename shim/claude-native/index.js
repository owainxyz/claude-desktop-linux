"use strict";

const fs = require("fs");
const { execFile } = require("child_process");
const binding = require("./claude-native-binding.node");

const marker = "__cdl_path__";

function readFreshUserPath() {
  const shell = process.env.SHELL || "/bin/sh";
  return new Promise((resolve) => {
    execFile(
      shell,
      ["-lic", `printf '${marker}%s${marker}' "$PATH"`],
      { timeout: 8000, maxBuffer: 1 << 20, stdio: ["ignore", "pipe", "ignore"], env: { ...process.env, TERM: "dumb" } },
      (err, out) => {
        const m = new RegExp(`${marker}(.*?)${marker}`, "s").exec(String(out ?? ""));
        resolve(m && m[1] ? m[1] : process.env.PATH);
      },
    );
  });
}

function footprint(pid) {
  try {
    const roll = fs.readFileSync(`/proc/${pid}/smaps_rollup`, "utf8");
    const status = fs.readFileSync(`/proc/${pid}/status`, "utf8");
    const kb = (src, key) => Number(new RegExp(`^${key}:\\s+(\\d+) kB`, "m").exec(src)?.[1] ?? 0) * 1024;
    return { footprintBytes: kb(roll, "Pss"), commitBytes: kb(status, "RssAnon") + kb(status, "VmSwap"), creationTime: null };
  } catch {
    return null;
  }
}

class AuthRequest {
  static isAvailable() {
    return false;
  }
}

const native = {
  ...binding,
  AuthRequest,
  readRegistryValues: () => [],
  enumRegistrySubkeys: () => [],
  enumRegistryValues: () => [],
  registryKeyReadError: () => undefined,
  closeStartingDialog: () => {},
  getWindowsElevationType: () => undefined,
  readFreshUserPath,
  readProcessFootprints: async (pids) => pids.map(footprint),
  subscribeNetworkCost: () => false,
  cuIsRemoteSession: () => false,
};

if (process.env.CLAUDE_NATIVE_TRACE) {
  const seen = new Set();
  module.exports = new Proxy(native, {
    get(t, k) {
      if (typeof k === "string" && !(k in t) && !seen.has(k)) {
        seen.add(k);
        process.stderr.write(`[claude-native-linux] missing: ${k}\n`);
      }
      return t[k];
    },
  });
} else {
  module.exports = native;
}
