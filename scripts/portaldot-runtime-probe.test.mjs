import assert from "node:assert/strict";
import test from "node:test";
import { validateEndpoint, probePortaldot, ProbeError } from "./portaldot-runtime-probe.mjs";

const hash = (digit) => "0x" + digit.repeat(64);
const observations = {
  rpc_methods: { methods: ["system_chain", "system_properties", "state_getRuntimeVersion",
    "chain_getBlockHash", "chain_getFinalizedHead", "contracts_call"] },
  system_chain: "Portaldot",
  system_properties: { tokenSymbol: "POT", tokenDecimals: 14, ss58Format: 42 },
  state_getRuntimeVersion: { specName: "portaldot", specVersion: 1002, transactionVersion: 2 },
  chain_getBlockHash: hash("a"),
  chain_getFinalizedHead: hash("b")
};
function fakeRpc(overrides = {}) {
  return { async request(method) { return { ...observations, ...overrides }[method]; } };
}

test("reject insecure remote RPC and credentialed URLs", () => {
  assert.throws(() => validateEndpoint("ws://remote.example"), ProbeError);
  assert.throws(() => validateEndpoint("https://remote.example"), ProbeError);
  assert.throws(() => validateEndpoint("wss://user:secret@remote.example"), ProbeError);
  assert.equal(validateEndpoint("ws://localhost:9944/"), "ws://localhost:9944/");
  assert.equal(validateEndpoint("wss://remote.example/"), "wss://remote.example/");
});

test("never reports deployment readiness merely from chain RPC support", async () => {
  const report = await probePortaldot(fakeRpc(), {
    genesisHash: hash("a"), specName: "portaldot", specVersion: 1002
  });
  assert.equal(report.verdict, "BLOCKED");
  assert.equal(report.constraints.expectedIdentityMatched, true);
  assert.equal(report.constraints.hasContractsRpc, true);
  assert.equal(report.constraints.evmCompatibilityProven, false);
  assert.equal(report.constraints.realLifecycleReceiptProven, false);
});

test("wrong genesis, spec name or runtime revision fails identity match", async () => {
  for (const expected of [
    { genesisHash: hash("c"), specName: "portaldot", specVersion: 1002 },
    { genesisHash: hash("a"), specName: "different", specVersion: 1002 },
    { genesisHash: hash("a"), specName: "portaldot", specVersion: 999 }
  ]) {
    const report = await probePortaldot(fakeRpc(), expected);
    assert.equal(report.constraints.expectedIdentityMatched, false);
    assert.equal(report.verdict, "BLOCKED");
  }
});

test("absence of contracts RPC cannot be confused with a supported smart-contract chain", async () => {
  const withoutContracts = observations.rpc_methods.methods.filter((x) => !x.startsWith("contracts_"));
  const report = await probePortaldot(fakeRpc({ rpc_methods: { methods: withoutContracts } }));
  assert.equal(report.constraints.hasContractsRpc, false);
  assert.equal(report.verdict, "BLOCKED");
});

test("malformed genesis, head and runtime do not produce evidence", async () => {
  for (const override of [
    { chain_getBlockHash: "0x12" },
    { chain_getFinalizedHead: null },
    { state_getRuntimeVersion: { specName: "portaldot", specVersion: "1002" } }
  ]) await assert.rejects(probePortaldot(fakeRpc(override)), ProbeError);
});

test("missing required identity and finality RPC methods fails closed", async () => {
  await assert.rejects(probePortaldot(fakeRpc({
    rpc_methods: { methods: ["system_chain", "system_properties"] }
  })), /Missing required RPC method/);
});
