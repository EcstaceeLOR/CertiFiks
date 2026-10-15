#!/usr/bin/env node
/**
 * Read-only Portaldot Substrate RPC capability probe.
 * NEVER sends transactions, imports keys or treats a node as organizer-approved.
 * A checked-in manifest MUST be independently approved and cryptographically
 * bound to genesis hash and runtime identity before a deployment is considered.
 */
import { pathToFileURL } from "node:url";
import { writeFileSync } from "node:fs";

export class ProbeError extends Error {}

export function validateEndpoint(value) {
  const u = new URL(value);
  if (!["wss:", "ws:"].includes(u.protocol)) throw new ProbeError("Substrate RPC must use WS/WSS");
  if (u.username || u.password || u.search || u.hash) throw new ProbeError("RPC URL cannot carry secrets/query");
  if (u.protocol === "ws:" && !["localhost", "127.0.0.1", "[::1]"].includes(u.hostname)) {
    throw new ProbeError("Remote Substrate RPC requires wss://");
  }
  return u.toString();
}

export function createRpc(endpoint, WebSocketImpl = globalThis.WebSocket, timeoutMs = 12000) {
  if (typeof WebSocketImpl !== "function") throw new ProbeError("Node 22 WebSocket support is required");
  const url = validateEndpoint(endpoint);
  const socket = new WebSocketImpl(url);
  let serial = 0;
  const requests = new Map();
  let closed = false;
  const ready = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new ProbeError("WebSocket connect timeout")), timeoutMs);
    socket.addEventListener("open", () => { clearTimeout(timer); resolve(); }, { once: true });
    socket.addEventListener("error", () => { clearTimeout(timer); reject(new ProbeError("RPC WebSocket error")); }, { once: true });
    socket.addEventListener("close", () => { clearTimeout(timer); reject(new ProbeError("RPC WebSocket closed")); }, { once: true });
  });
  socket.addEventListener("message", (message) => {
    try {
      const response = JSON.parse(String(message.data));
      const pending = requests.get(response.id);
      if (!pending) return;
      clearTimeout(pending.timer);
      requests.delete(response.id);
      if (response.error) pending.reject(new ProbeError(`RPC ${pending.method}: ${response.error.message || "unknown error"}`));
      else pending.resolve(response.result);
    } catch {
      // Ignore unsolicited or malformed messages; pending requests time out.
    }
  });
  socket.addEventListener("close", () => {
    closed = true;
    for (const pending of requests.values()) {
      clearTimeout(pending.timer);
      pending.reject(new ProbeError("RPC connection closed"));
    }
    requests.clear();
  });
  return {
    async request(method, params = []) {
      await ready;
      if (closed) throw new ProbeError("RPC is closed");
      const id = ++serial;
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => { requests.delete(id); reject(new ProbeError(`RPC ${method} timeout`)); }, timeoutMs);
        requests.set(id, { resolve, reject, timer, method });
        socket.send(JSON.stringify({ jsonrpc: "2.0", id, method, params }));
      });
    },
    close() { socket.close(); }
  };
}

export async function probePortaldot(rpc, expected = {}) {
  const methodsResponse = await rpc.request("rpc_methods");
  const methods = methodsResponse?.methods;
  if (!Array.isArray(methods)) throw new ProbeError("rpc_methods result invalid");
  const required = ["system_chain", "system_properties", "state_getRuntimeVersion", "chain_getBlockHash", "chain_getFinalizedHead"];
  for (const method of required) if (!methods.includes(method)) throw new ProbeError(`Missing required RPC method: ${method}`);
  const [chain, properties, runtime, genesisHash, finalizedHead] = await Promise.all([
    rpc.request("system_chain"),
    rpc.request("system_properties"),
    rpc.request("state_getRuntimeVersion"),
    rpc.request("chain_getBlockHash", [0]),
    rpc.request("chain_getFinalizedHead")
  ]);
  if (typeof chain !== "string" || !chain || !properties || typeof runtime?.specName !== "string" ||
      !Number.isInteger(runtime?.specVersion) || !/^0x[0-9a-fA-F]{64}$/.test(genesisHash ?? "") ||
      !/^0x[0-9a-fA-F]{64}$/.test(finalizedHead ?? "")) {
    throw new ProbeError("Incomplete or invalid chain identity/finality response");
  }
  const contractRpcMethods = methods.filter((name) => name.startsWith("contracts_"));
  const identityMatched = Boolean(
    expected.genesisHash && expected.specName &&
    Number.isInteger(expected.specVersion) &&
    genesisHash.toLowerCase() === expected.genesisHash.toLowerCase() &&
    runtime.specName === expected.specName &&
    runtime.specVersion === expected.specVersion
  );
  return {
    schemaVersion: 1,
    protocol: "substrate-jsonrpc",
    observed: { chain, genesisHash, finalizedHead, specName: runtime.specName,
      specVersion: runtime.specVersion, transactionVersion: runtime.transactionVersion ?? null,
      tokenSymbol: properties.tokenSymbol ?? null, tokenDecimals: properties.tokenDecimals ?? null,
      ss58Format: properties.ss58Format ?? null, contractRpcMethods },
    constraints: { expectedIdentityProvided: Boolean(expected.genesisHash && expected.specName && Number.isInteger(expected.specVersion)),
      expectedIdentityMatched: identityMatched,
      hasContractsRpc: contractRpcMethods.length > 0,
      evmCompatibilityProven: false,
      deployedCustodyContractProven: false,
      organizerRuntimeApprovalProven: false,
      realLifecycleReceiptProven: false },
    verdict: "BLOCKED",
    reason: "Read-only RPC introspection cannot certify approved runtime, compatible contract code, authorized custody, or real lifecycle transactions"
  };
}

export async function main(args = process.argv.slice(2)) {
  const endpoint = process.env.PORTALDOT_RPC_WS;
  if (!endpoint) throw new ProbeError("Set PORTALDOT_RPC_WS to the intended WebSocket endpoint");
  const expected = {
    genesisHash: process.env.PORTALDOT_EXPECTED_GENESIS,
    specName: process.env.PORTALDOT_EXPECTED_SPEC_NAME,
    specVersion: process.env.PORTALDOT_EXPECTED_SPEC_VERSION
      ? Number(process.env.PORTALDOT_EXPECTED_SPEC_VERSION) : undefined
  };
  const rpc = createRpc(endpoint);
  try {
    const report = await probePortaldot(rpc, expected);
    if (args.includes("--write")) {
      writeFileSync("portaldot-runtime-observation.json", JSON.stringify(report, null, 2) + "\n", { flag: "w" });
    }
    process.stdout.write(JSON.stringify(report, null, 2) + "\n");
    // Never return success as if this is approved deployment evidence.
    if (args.includes("--require-ready")) process.exitCode = 2;
  } finally { rpc.close(); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`Portaldot preflight blocked: ${error.message}\n`);
    process.exitCode = 1;
  });
}
