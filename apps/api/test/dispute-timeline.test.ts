import assert from "node:assert/strict";
import test from "node:test";
import { PrivateDisputeTimelineClientV1 } from "../src/disputes/timeline.js";

const ORG = "20000000-0000-4000-8000-000000000001";
const DISPUTE = "b0000000-0000-4000-8000-000000000001";
const ACTOR = "10000000-0000-4000-8000-000000000003";
const entry = {
  timeline_id: "c0000000-0000-4000-8000-000000000001",
  organization_id: ORG,
  dispute_id: DISPUTE,
  actor_user_id: ACTOR,
  kind: "arbitrator_note",
  reason_digest: "0x" + "d".repeat(64),
  artifact_digest: null,
  event_idempotency: "a".repeat(64),
  created_at: "2026-10-26T15:00:00.000Z",
};

test("private timeline uses exact server-side RPC and never emits payout authorization", async () => {
  const fetcher = (async (url: string, init?: RequestInit) => {
    assert.equal(
      url,
      "https://tenant-db.supabase.co/rest/v1/rpc/certifiks_read_dispute_timeline",
    );
    assert.equal(init?.method, "POST");
    assert.equal(init?.redirect, "error");
    assert.equal(
      new Headers(init?.headers).get("Authorization"),
      "Bearer server-test-secret-long",
    );
    assert.deepEqual(JSON.parse(String(init?.body)), {
      p_org: ORG,
      p_dispute: DISPUTE,
      p_actor: ACTOR,
      p_limit: 10,
    });
    return new Response(JSON.stringify([entry]), { status: 200 });
  }) as typeof fetch;
  const client = new PrivateDisputeTimelineClientV1(
    "https://tenant-db.supabase.co",
    "server-test-secret-long",
    fetcher,
  );
  const result = await client.list(ORG, DISPUTE, ACTOR, 10);
  assert.equal(result.length, 1);
  assert.equal(result[0].settlementAuthorized, false);
  assert.equal(result[0].reasonDigest, entry.reason_digest);
  assert.equal("artifact_storage_key" in result[0], false);
});

test("rejects wrong identities and cross-tenant case leaks", async () => {
  let rows = [
    { ...entry, organization_id: "20000000-0000-4000-8000-000000000002" },
  ];
  const client = new PrivateDisputeTimelineClientV1(
    "https://tenant-db.supabase.co",
    "server-test-secret-long",
    (async () =>
      new Response(JSON.stringify(rows), { status: 200 })) as typeof fetch,
  );
  await assert.rejects(
    client.list(ORG, DISPUTE, "tampered"),
    /DISPUTE_TIMELINE_UNAVAILABLE/,
  );
  await assert.rejects(
    client.list(ORG, DISPUTE, ACTOR),
    /DISPUTE_TIMELINE_UNAVAILABLE/,
  );
  rows = [{ ...entry, reason_digest: "tampered" }];
  await assert.rejects(
    client.list(ORG, DISPUTE, ACTOR),
    /DISPUTE_TIMELINE_UNAVAILABLE/,
  );
});

test("database refusal cannot turn into fabricated dispute resolution", async () => {
  const client = new PrivateDisputeTimelineClientV1(
    "https://tenant-db.supabase.co",
    "server-test-secret-long",
    (async () => new Response("forbidden", { status: 403 })) as typeof fetch,
  );
  await assert.rejects(
    client.list(ORG, DISPUTE, ACTOR),
    /DISPUTE_TIMELINE_UNAVAILABLE/,
  );
});
