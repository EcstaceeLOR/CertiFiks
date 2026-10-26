import assert from "node:assert/strict";
import test from "node:test";
import { ServerVerifierReviewClientV1 } from "../src/reviews/verifier-preflight.js";

const ORG = "20000000-0000-4000-8000-000000000001";
const ACTOR = "10000000-0000-4000-8000-000000000003";
const row = {
  organization_id: ORG,
  bounty_id: "30000000-0000-4000-8000-000000000001",
  attempt_id: "60000000-0000-4000-8000-000000000001",
  run_id: "70000000-0000-4000-8000-000000000001",
  base_commit_sha: "b".repeat(40),
  head_commit_sha: "c".repeat(40),
  funded_manifest_digest: "0x" + "a".repeat(64),
  plan_digest: "0x" + "d".repeat(64),
  runner_image_digest: "0x" + "e".repeat(64),
  result_digest: "0x" + "9".repeat(64),
  runner_outcome: "needs_review",
  completed_at: "2026-10-26T10:00:00.000Z",
  artifact_count: 3,
  can_attest: false,
  payout_authorized: false,
};

test("verifier queue reads fixed server RPC with trusted actor and disallows signing", async () => {
  let calls = 0;
  const mock = (async (url: string, request?: RequestInit) => {
    calls++;
    assert.equal(url, "https://reviewer-test.supabase.co/rest/v1/rpc/certifiks_verifier_review_preflight");
    assert.equal(request?.method, "POST");
    assert.equal(request?.redirect, "error");
    assert.equal(
      new Headers(request?.headers).get("Authorization"),
      "Bearer reviewer-test-service-key",
    );
    assert.deepEqual(JSON.parse(String(request?.body)), {
      p_organization_id: ORG,
      p_actor_user_id: ACTOR,
      p_limit: 10,
    });
    return new Response(JSON.stringify([row]), { status: 200 });
  }) as typeof fetch;
  const reader = new ServerVerifierReviewClientV1(
    "https://reviewer-test.supabase.co",
    "reviewer-test-service-key",
    mock,
  );
  const result = await reader.list(ORG, ACTOR, 10);
  assert.equal(calls, 1);
  assert.equal(result.length, 1);
  assert.equal(result[0].canAttest, false);
  assert.equal(result[0].payoutAuthorized, false);
  assert.equal(result[0].baseCommitSha, "b".repeat(40));
});

test("rejects untrusted identity, cross-tenant rows and forged signer flags", async () => {
  let responseRows = [{ ...row, organization_id: "20000000-0000-4000-8000-000000000002" }];
  const reader = new ServerVerifierReviewClientV1(
    "https://reviewer-test.supabase.co",
    "reviewer-test-service-key",
    (async () => new Response(JSON.stringify(responseRows), { status: 200 })) as typeof fetch,
  );
  await assert.rejects(reader.list(ORG, "not-uuid", 10), /VERIFIER_PREFLIGHT_BLOCKED/);
  await assert.rejects(reader.list(ORG, ACTOR, 10), /cross-tenant/);
  responseRows = [{ ...row, can_attest: true }] as typeof responseRows;
  await assert.rejects(reader.list(ORG, ACTOR, 10), /unauthorized signer/);
  responseRows = [{ ...row, result_digest: "tampered" }];
  await assert.rejects(reader.list(ORG, ACTOR, 10), /reported result digest/);
});

test("unavailable or unauthorized upstream must never report verified evidence", async () => {
  const reader = new ServerVerifierReviewClientV1(
    "https://reviewer-test.supabase.co",
    "reviewer-test-service-key",
    (async () => new Response("not authorized", { status: 403 })) as typeof fetch,
  );
  await assert.rejects(reader.list(ORG, ACTOR), /authorization or database unavailable/);
});

test("unsafe backend origins and credentials are blocked", () => {
  for (const origin of [
    "http://reviewer-test.supabase.co",
    "https://example.org",
    "https://reviewer-test.supabase.co/?key=bad",
  ]) {
    assert.throws(
      () => new ServerVerifierReviewClientV1(origin, "reviewer-test-service-key"),
      /VERIFIER_PREFLIGHT_BLOCKED/,
    );
  }
});
