"use strict";

const binding = require("./claude-native-binding.node");

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
  readFreshUserPath: () => undefined,
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
