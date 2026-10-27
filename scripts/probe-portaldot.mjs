#!/usr/bin/env node
/**
 * Read-only compatibility probe for a candidate Portaldot Substrate WebSocket.
 * Requires Node.js >=22 (global WebSocket); no external dependencies or secrets.
 * Usage: PORTALDOT_WS_RPC=wss://... node scripts/probe-portaldot.mjs
 *
 * NOTE: Success proves RPC accessibility ONLY, not contract deployment,
 * hackathon eligibility, EVM compatibility or live safety.
 */

// This public V3 testnet URL is a read-only discovery candidate from the
// October 2026 network announcement, not independently approved by CertiFiks.
const candidate =
  process.env.PORTALDOT_WS_RPC || "wss://test-node-v3.portaldot.dev";
const timeoutMs = Math.min(
  30000,
  Math.max(2000, Number(process.env.RPC_TIMEOUT_MS || 12000)),
);
const allowed = /^(wss?:)\/\//i.test(candidate);
if (!allowed) {
  console.error("PORTALDOT_WS_RPC must start with ws:// or wss://");
  process.exit(2);
}
const u = new URL(candidate);
if (u.username || u.password || u.search || u.hash) {
  console.error(
    "Refusing to probe URL containing credentials, tokens, query or fragment.",
  );
  process.exit(2);
}
if (
  u.protocol !== "wss:" &&
  !["localhost", "127.0.0.1", "[::1]"].includes(u.hostname)
) {
  console.error("Non-local RPC requires wss:// TLS.");
  process.exit(2);
}

const methods = [
  "rpc_methods",
  "system_chain",
  "system_properties",
  "system_version",
  "state_getRuntimeVersion",
  "chain_getHeader",
  "chain_getBlockHash",
  "chain_getFinalizedHead",
  "eth_chainId",
  "eth_blockNumber",
];
const started = new Date().toISOString();
const results = Object.fromEntries(
  methods.map((name) => [name, { status: "not_run" }]),
);
let socket;
const responses = new Map();
let connectionError = null;
let connected = false;

function withTimeout(promise, ms, label) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("timeout: " + label)), ms);
    Promise.resolve(promise).then(
      (val) => {
        clearTimeout(timer);
        resolve(val);
      },
      (err) => {
        clearTimeout(timer);
        reject(err);
      },
    );
  });
}

try {
  socket = new WebSocket(candidate);
  const opened = new Promise((resolve, reject) => {
    socket.addEventListener(
      "open",
      () => {
        connected = true;
        resolve();
      },
      { once: true },
    );
    socket.addEventListener(
      "error",
      () => reject(new Error("websocket handshake or network error")),
      { once: true },
    );
    socket.addEventListener(
      "close",
      () => {
        if (!connected) reject(new Error("socket closed before handshake"));
      },
      { once: true },
    );
  });
  await withTimeout(opened, timeoutMs, "opening websocket");

  socket.addEventListener("message", (event) => {
    try {
      const parsed = JSON.parse(String(event.data));
      const messages = Array.isArray(parsed) ? parsed : [parsed];
      for (const message of messages) {
        const pending = responses.get(message.id);
        if (pending) {
          responses.delete(message.id);
          pending.resolve(message);
        }
      }
    } catch {
      // Ignore non-JSON, unsolicited or malformed messages.
    }
  });
  let id = 1;
  for (const method of methods) {
    const requestId = id++;
    const promise = new Promise((resolve, reject) => {
      responses.set(requestId, { resolve, reject });
      // A no-argument chain_getBlockHash returns the best block on many
      // Substrate nodes, NOT the immutable genesis. Pin block zero explicitly.
      const params = method === "chain_getBlockHash" ? [0] : [];
      socket.send(
        JSON.stringify({ jsonrpc: "2.0", id: requestId, method, params }),
      );
    });
    try {
      const response = await withTimeout(promise, timeoutMs, method);
      if (response.error) {
        results[method] = {
          status: response.error.code === -32601 ? "unsupported" : "rpc_error",
          error_code: response.error.code,
          error_message: String(response.error.message || "").slice(0, 200),
        };
      } else {
        let result = response.result;
        // Avoid dumping all enabled methods or private messages in CI output.
        if (method === "rpc_methods") {
          const advertised = Array.isArray(result?.methods)
            ? result.methods
            : [];
          result = {
            total: advertised.length,
            supports_substrate_contracts: advertised.filter((m) =>
              m.startsWith("contracts_"),
            ),
            supports_evm_rpc: advertised.filter((m) => m.startsWith("eth_")),
            supports_system: advertised.includes("system_chain"),
            supports_runtime: advertised.includes("state_getRuntimeVersion"),
          };
        }
        results[method] = { status: "ok", result };
      }
    } catch (err) {
      results[method] = {
        status: "failed",
        error: String(err.message || err).slice(0, 200),
      };
    } finally {
      responses.delete(requestId);
    }
  }
} catch (err) {
  connectionError = String(err.message || err);
  for (const name of methods)
    if (results[name].status === "not_run")
      results[name] = { status: "skipped", reason: "connection failed" };
} finally {
  if (socket) {
    try {
      socket.close(1000, "probe complete");
    } catch {}
  }
}

const outcome = {
  schema_version: 1,
  timestamp_utc: started,
  rpc_endpoint: u.origin + u.pathname,
  websocket_opened: connected,
  connection_error: connectionError,
  network_read_only: true,
  methods: results,
  caveats: [
    "Read-only probe; no real contract was deployed and no fees were spent.",
    "RPC method availability is not proof of compatible WASM/ink! ABI.",
    "EVM compatibility requires working eth RPC, EVM account model and successful deployment, not an unsupported method.",
    "chain_getBlockHash is explicitly queried at height zero for read-only genesis identity.",
    "Hackathon eligibility requires current organizer confirmation.",
  ],
};
console.log(JSON.stringify(outcome, null, 2));
if (
  !connected ||
  results.system_chain.status !== "ok" ||
  results.state_getRuntimeVersion.status !== "ok"
)
  process.exitCode = 1;
