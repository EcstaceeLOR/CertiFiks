import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import {
  parsePayoutProofConfig,
  PayoutProofError,
  verifyFinalizedNativeWithdrawal,
  WITHDRAWN_TOPIC,
} from "./finalized-withdrawal.mjs";

const addr = (letter) => "0x" + letter.repeat(40);
const hash = (letter) => "0x" + letter.repeat(64);
const topicAddress = (letter) => "0x" + "0".repeat(24) + letter.repeat(40);
const word = (value) => BigInt(value).toString(16).padStart(64, "0");
const config = {
  rpcOrigin: "https://synthetic-rpc.example.net",
  chainId: "31337",
  genesisHash: hash("1"),
  escrowAddress: addr("a"),
  escrowCodeSha256: createHash("sha256")
    .update(Buffer.from("6000", "hex")).digest("hex"),
  transactionHash: hash("3"),
  logIndex: "0x2",
  bountyId: "19",
  beneficiary: addr("b"),
  recipient: addr("c"),
  amountAtoms: "1200",
  remainingAtoms: "300",
};

function upstream(overrides = {}) {
  const receipt = {
    transactionHash: config.transactionHash,
    to: config.escrowAddress,
    status: "0x1",
    blockHash: hash("4"),
    blockNumber: "0xa",
    logs: [{
      address: config.escrowAddress,
      transactionHash: config.transactionHash,
      blockHash: hash("4"),
      blockNumber: "0xa",
      logIndex: config.logIndex,
      topics: [WITHDRAWN_TOPIC, hash("0").slice(0, 26) + word(19).slice(24),
        topicAddress("b"), topicAddress("c")],
      data: "0x" + word(1200) + word(300),
      removed: false,
    }],
  };
  // Override one result by RPC method without weakening core witness checks.
  const responses = {
    eth_chainId: "0x7a69",
    eth_getTransactionReceipt: receipt,
    eth_getCode: "0x6000",
  };
  const calls = [];
  const fetchStub = async (url, init) => {
    assert.equal(url, config.rpcOrigin);
    assert.equal(init?.method, "POST");
    assert.equal(init?.redirect, "error");
    assert.equal(init?.cache, "no-store");
    const message = JSON.parse(String(init.body));
    calls.push(message.method);
    let result;
    if (message.method === "eth_getBlockByNumber") {
      const name = message.params[0];
      result = name === "0x0"
        ? { number: "0x0", hash: config.genesisHash }
        : name === "finalized"
          ? { number: "0x10", hash: hash("5") }
          : { number: "0xa", hash: receipt.blockHash };
      if (name === "0x0" && Object.hasOwn(overrides, "genesis")) result = overrides.genesis;
      if (name === "finalized" && Object.hasOwn(overrides, "finalized")) result = overrides.finalized;
      if (name === "0xa" && Object.hasOwn(overrides, "canonical")) result = overrides.canonical;
    } else {
      result = Object.hasOwn(overrides, message.method)
        ? overrides[message.method] : responses[message.method];
    }
    return new Response(JSON.stringify({ jsonrpc: "2.0", id: message.id, result }), {
      status: 200,
    });
  };
  return { fetchStub, receipt, calls };
}

test("finalized witness binds configured chain, code, transaction and exact event log", async () => {
  const mock = upstream();
  const evidence = await verifyFinalizedNativeWithdrawal(config, mock.fetchStub);
  assert.deepEqual(mock.calls, [
    "eth_chainId", "eth_getBlockByNumber", "eth_getTransactionReceipt",
    "eth_getBlockByNumber", "eth_getBlockByNumber", "eth_getCode",
  ]);
  assert.equal(evidence.witness, "finalized_native_withdrawal_event");
  assert.equal(evidence.verifiedOnConfiguredRpc, true);
  assert.equal(evidence.productReady, false);
  assert.equal(evidence.securityAuditApproved, false);
  assert.equal(evidence.amountAtoms, "1200");
  assert.equal(evidence.remainingAtoms, "300");
  assert.equal(evidence.blockNumber, "10");
  assert.equal(evidence.transactionHash, config.transactionHash);
});

test("missing finality, canonicality or transaction success fail closed", async () => {
  const cases = [
    { eth_chainId: "0x1" },
    { genesis: { number: "0x0", hash: hash("f") } },
    { eth_getTransactionReceipt: { ...upstream().receipt, status: "0x0" } },
    { eth_getTransactionReceipt: { ...upstream().receipt, to: addr("d") } },
    { finalized: { number: "0x9", hash: hash("5") } },
    { finalized: null },
    { canonical: { number: "0xa", hash: hash("6") } },
    { eth_getCode: "0x6001" },
  ];
  for (const value of cases) {
    await assert.rejects(
      verifyFinalizedNativeWithdrawal(config, upstream(value).fetchStub),
      PayoutProofError,
    );
  }
});

test("a valid-looking receipt with a forged or wrong log is never a payment", async () => {
  const modify = [
    (r) => { r.logs[0].topics[0] = hash("e"); },
    (r) => { r.logs[0].topics[1] = "0x" + word(20); },
    (r) => { r.logs[0].topics[2] = topicAddress("d"); },
    (r) => { r.logs[0].topics[3] = topicAddress("d"); },
    (r) => { r.logs[0].data = "0x" + word(1199) + word(300); },
    (r) => { r.logs[0].data = "0x" + word(1200) + word(301); },
    (r) => { r.logs[0].logIndex = "0x3"; },
    (r) => { r.logs[0].blockHash = hash("f"); },
    (r) => { r.logs[0].removed = true; },
    (r) => { r.logs[0].address = addr("f"); },
  ];
  for (const change of modify) {
    const bad = structuredClone(upstream().receipt);
    change(bad);
    await assert.rejects(
      verifyFinalizedNativeWithdrawal(
        config, upstream({ eth_getTransactionReceipt: bad }).fetchStub,
      ),
      PayoutProofError,
    );
  }
});

test("reject untrusted environment, ambiguous amounts, and non-HTTPS RPC origins", () => {
  for (const value of [
    { ...config, rpcOrigin: "http://synthetic-rpc.example.net" },
    { ...config, rpcOrigin: "https://synthetic-rpc.example.net/?token=private" },
    { ...config, chainId: "0" },
    { ...config, chainId: "31337.5" },
    { ...config, bountyId: "01" },
    { ...config, amountAtoms: "0" },
    { ...config, amountAtoms: "1.5" },
    { ...config, amountAtoms: "-1" },
    { ...config, remainingAtoms: "999999999999999999999999999999999999999999999999999999999999999999999999999999" },
    { ...config, transactionHash: hash("f").slice(2) },
    { ...config, fakeProductionApproval: true },
  ]) {
    assert.throws(() => parsePayoutProofConfig(value), PayoutProofError);
  }
});
