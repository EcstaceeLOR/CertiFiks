import assert from "node:assert/strict";
import test from "node:test";
import {
  ChainIndexerBlockedError,
  DurableEvmIndexStepV1,
} from "../src/chain/durable-evm-step.js";
import type { EvmObservationConfigV1 } from "../src/chain/evm-observer.js";

const genesis = "0x" + "a".repeat(64);
const block = "0x" + "b".repeat(64);
const contract = "0x" + "c".repeat(40);
const topic = "0x" + "d".repeat(64);
const config: EvmObservationConfigV1 = {
  rpcHttpsUrl: "https://approved.example.org/jsonrpc",
  approvedChainId: "31337",
  approvedGenesisHash: genesis,
  contractAddresses: [contract],
  eventTopic0: [topic],
};

function rpcFetch(): typeof fetch {
  return (async (_url: string, options?: RequestInit) => {
    const { method, params } = JSON.parse(String(options?.body));
    const result = method === "eth_chainId" ? "0x7a69"
      : method === "eth_blockNumber" ? "0x4"
        : method === "eth_getLogs" ? []
          : params[0] === "0x0"
            ? { number: "0x0", hash: genesis }
            : { number: "0x1", hash: block, parentHash: genesis };
    return new Response(JSON.stringify({ jsonrpc: "2.0", id: 1, result }), { status: 200 });
  }) as typeof fetch;
}

test("reads approved cursor then atomically records one independently checked block", async () => {
  const writes: unknown[] = [];
  const databaseFetch = (async (url: string, options?: RequestInit) => {
    assert.ok(String(url).startsWith("https://sandbox.supabase.co/rest/v1/"));
    assert.equal(
      new Headers(options?.headers).get("Authorization"),
      "Bearer server-side-test-key-long",
    );
    if (options?.method === "GET") {
      return new Response(JSON.stringify([{
        genesis_hash: genesis,
        last_hash: genesis,
        last_scanned: "0",
        confirmation_depth: 2,
        halted: false,
      }]), { status: 200 });
    }
    writes.push(JSON.parse(String(options?.body)));
    return new Response(JSON.stringify("accepted"), { status: 200 });
  }) as typeof fetch;
  const step = new DurableEvmIndexStepV1(
    config, "https://sandbox.supabase.co",
    "server-side-test-key-long", rpcFetch(), databaseFetch,
  );
  assert.equal(await step.pollOnce(), "accepted");
  assert.equal(writes.length, 1);
  assert.deepEqual(Object.keys(writes[0] as object).sort(), [
    "p_chain_id", "p_hash", "p_logs", "p_number", "p_observed_head", "p_parent",
  ]);
  const record = writes[0] as Record<string, unknown>;
  assert.equal(record.p_hash, block);
  assert.equal(record.p_number, "1");
  assert.deepEqual(record.p_logs, []);
  assert.equal("p_release_funds" in record, false);
});

test("cursor-chain mismatch, halted cursor and parent reorg never write any observations", async () => {
  for (const edit of [
    { genesis_hash: "0x" + "e".repeat(64) },
    { halted: true },
    { last_hash: "0x" + "f".repeat(64) },
  ]) {
    let writes = 0;
    const databaseFetch = (async (_url: string, options?: RequestInit) => {
      if (options?.method === "POST") {
        writes++;
        throw new Error("should not write");
      }
      return new Response(JSON.stringify([{
        genesis_hash: genesis,
        last_hash: genesis,
        last_scanned: 0,
        halted: false,
        ...edit,
      }]), { status: 200 });
    }) as typeof fetch;
    const step = new DurableEvmIndexStepV1(
      config, "https://sandbox.supabase.co",
      "server-side-test-key-long", rpcFetch(), databaseFetch,
    );
    await assert.rejects(step.pollOnce(), ChainIndexerBlockedError);
    assert.equal(writes, 0);
  }
});

test("database outage never becomes a verified blockchain transaction", async () => {
  const step = new DurableEvmIndexStepV1(
    config, "https://sandbox.supabase.co",
    "server-side-test-key-long", rpcFetch(),
    (async () => new Response("offline", { status: 503 })) as typeof fetch,
  );
  await assert.rejects(step.pollOnce(), ChainIndexerBlockedError);
});
