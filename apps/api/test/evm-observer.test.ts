import assert from "node:assert/strict";
import test from "node:test";
import {
  ChainObservationError,
  type EvmObservationConfigV1,
  ReadOnlyEvmObserverV1,
} from "../src/chain/evm-observer.js";

const genesis = "0x" + "a".repeat(64);
const blockHash = "0x" + "b".repeat(64);
const address = "0x" + "c".repeat(40);
const topic = "0x" + "d".repeat(64);
const transactionHash = "0x" + "e".repeat(64);
const config: EvmObservationConfigV1 = {
  rpcHttpsUrl: "https://testnode.example.org/jsonrpc",
  approvedChainId: "31337",
  approvedGenesisHash: genesis,
  contractAddresses: [address],
  eventTopic0: [topic],
};

function rpcFetch(overrides: Record<string, unknown> = {}): typeof fetch {
  return (async (url: string, init?: RequestInit) => {
    assert.equal(String(url), config.rpcHttpsUrl);
    assert.equal(init?.method, "POST");
    assert.equal(init?.redirect, "error");
    const req = JSON.parse(String(init?.body)) as {
      method: string;
      params: unknown[];
    };
    let result: unknown;
    switch (req.method) {
      case "eth_chainId":
        result = overrides.chainId ?? "0x7a69";
        break;
      case "eth_blockNumber":
        result = "0x5";
        break;
      case "eth_getBlockByNumber":
        result =
          req.params[0] === "0x0"
            ? { number: "0x0", hash: overrides.genesis ?? genesis }
            : {
                number: "0x1",
                hash: overrides.reorgHash ?? blockHash,
                parentHash: genesis,
              };
        break;
      case "eth_getLogs":
        result = [
          {
            blockHash: overrides.logBlockHash ?? blockHash,
            blockNumber: "0x1",
            transactionHash,
            logIndex: "0x0",
            address: overrides.logAddress ?? address,
            topics: [topic],
            data: "0x1234",
            removed: false,
          },
        ];
        break;
      default:
        throw new Error("Unexpected RPC method");
    }
    return new Response(JSON.stringify({ jsonrpc: "2.0", id: 1, result }), {
      status: 200,
    });
  }) as typeof fetch;
}

test("indexes only verified chain genesis, pinned contract and canonical block events", async () => {
  const observer = new ReadOnlyEvmObserverV1(config, rpcFetch());
  const observed = await observer.observeBlock(1);
  assert.equal(observed.blockHash, blockHash);
  assert.equal(observed.chainId, "31337");
  assert.equal(observed.parentHash, genesis);
  assert.equal(observed.observedHead, "5");
  assert.deepEqual(
    observed.logs.map((event) => [
      event.transactionHash,
      event.logIndex,
      event.address,
    ]),
    [[transactionHash, "0", address]],
  );
  assert.match(observed.logs[0].dataSha256, /^0x[a-f0-9]{64}$/);
});

test("rejects malicious chain identity and wrong genesis", async () => {
  for (const override of [
    { chainId: "0x1" },
    { genesis: "0x" + "f".repeat(64) },
  ]) {
    await assert.rejects(
      new ReadOnlyEvmObserverV1(config, rpcFetch(override)).observeBlock(1),
      (error: unknown) =>
        error instanceof ChainObservationError &&
        error.reason === "UNAPPROVED_CHAIN",
    );
  }
});

test("rejects unapproved contract events and log/block reorg disagreement", async () => {
  const attempts = [
    {
      override: { logAddress: "0x" + "f".repeat(40) },
      reason: "UNAPPROVED_CONTRACT",
    },
    { override: { logBlockHash: "0x" + "f".repeat(64) }, reason: "REORG" },
    { override: { reorgHash: "0x" + "f".repeat(64) }, reason: "REORG" },
  ];
  for (const item of attempts) {
    await assert.rejects(
      new ReadOnlyEvmObserverV1(config, rpcFetch(item.override)).observeBlock(
        1,
      ),
      (error: unknown) =>
        error instanceof ChainObservationError && error.reason === item.reason,
    );
  }
});

test("does not silently fall back to unapproved or non-TLS endpoints", () => {
  for (const rpcHttpsUrl of [
    "http://testnode.example.org",
    "https://user:pass@testnode.example.org",
    "https://testnode.example.org/?token=secret",
  ]) {
    assert.throws(
      () => new ReadOnlyEvmObserverV1({ ...config, rpcHttpsUrl }),
      (error: unknown) =>
        error instanceof ChainObservationError &&
        error.reason === "UNAPPROVED_CHAIN",
    );
  }
});

test("RPC outage cannot be mistaken for real chain evidence", async () => {
  const observer = new ReadOnlyEvmObserverV1(config, (async () => {
    throw new Error("connection refused");
  }) as typeof fetch);
  await assert.rejects(
    observer.observeBlock(1),
    (error: unknown) =>
      error instanceof ChainObservationError &&
      error.reason === "PROVIDER_UNAVAILABLE",
  );
});
