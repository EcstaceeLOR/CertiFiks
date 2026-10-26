import assert from "node:assert/strict";
import test from "node:test";
import {
  ServerVerificationQueueV1,
  VerificationQueueError,
} from "../src/job-queue.js";

const ORG = "20000000-0000-4000-8000-000000000001";
const BOUNTY = "30000000-0000-4000-8000-000000000001";
const ATTEMPT = "60000000-0000-4000-8000-000000000001";
const JOB = "90000000-0000-4000-8000-000000000001";
const LEASE = "90000000-0000-4000-8000-000000000002";
const MANIFEST = "0x" + "a".repeat(64);

const sample = {
  job_id: JOB,
  organization_id: ORG,
  bounty_id: BOUNTY,
  attempt_id: ATTEMPT,
  manifest_digest: MANIFEST,
  stage: "baseline",
  status: "running" as const,
  attempts: 1,
  lease_id: LEASE,
  lease_until: "2026-10-26T12:00:00.000Z",
};

test("job transport is fixed to trusted PostgREST RPC and never includes payment mutation", async () => {
  const seen: { name: string; body: Record<string, unknown> }[] = [];
  const mock = (async (url: string, options?: RequestInit) => {
    const path = new URL(url).pathname;
    const name = path.split("/").at(-1) ?? "";
    assert.ok(
      String(url).startsWith("https://mytest.supabase.co/rest/v1/rpc/"),
    );
    assert.equal(options?.method, "POST");
    assert.equal(options?.redirect, "error");
    assert.equal(
      new Headers(options?.headers).get("Authorization"),
      "Bearer mock-service-key-long-enough",
    );
    const body = JSON.parse(String(options?.body)) as Record<string, unknown>;
    seen.push({ name, body });
    const reply =
      name === "certifiks_claim_verification_jobs"
        ? [sample]
        : name === "certifiks_enqueue_verification_stage"
          ? JOB
          : true;
    return new Response(JSON.stringify(reply), { status: 200 });
  }) as typeof fetch;
  const queue = new ServerVerificationQueueV1(
    "https://mytest.supabase.co",
    "mock-service-key-long-enough",
    mock,
  );
  assert.equal(
    await queue.enqueue(ORG, BOUNTY, ATTEMPT, MANIFEST, "baseline"),
    JOB,
  );
  const [leased] = await queue.claim(1);
  assert.equal(leased.job_id, JOB);
  assert.equal(await queue.heartbeat(leased), true);
  assert.equal(await queue.complete(leased, false, "RUNNER_CRASHED"), true);
  assert.equal(await queue.cancel(JOB, "POLICY_REVOKED"), true);
  assert.deepEqual(
    seen.map(({ name }) => name),
    [
      "certifiks_enqueue_verification_stage",
      "certifiks_claim_verification_jobs",
      "certifiks_heartbeat_verification_job",
      "certifiks_complete_verification_job",
      "certifiks_cancel_verification_job",
    ],
  );
  assert.equal(
    seen.some(({ name }) => name.includes("payment")),
    false,
  );
  assert.equal(JSON.stringify(seen).includes("mock-service-key"), false);
  assert.equal(seen[3].body.p_lease, LEASE);
  assert.equal(seen[3].body.p_attempt, 1);
});

test("unsigned, malformed or cross-tenant-shaped queue envelopes fail closed", async () => {
  let called = 0;
  const mock = (async () => {
    called++;
    return new Response(JSON.stringify([{ ...sample, lease_id: "" }]), {
      status: 200,
    });
  }) as typeof fetch;
  const queue = new ServerVerificationQueueV1(
    "https://mytest.supabase.co",
    "mock-service-key-long-enough",
    mock,
  );
  await assert.rejects(
    queue.enqueue(ORG, BOUNTY, ATTEMPT, "not-digest", "baseline"),
    VerificationQueueError,
  );
  await assert.rejects(
    queue.enqueue(ORG, BOUNTY, ATTEMPT, MANIFEST, "pay"),
    VerificationQueueError,
  );
  await assert.rejects(queue.claim(0), VerificationQueueError);
  assert.equal(called, 0);
  await assert.rejects(queue.claim(1), VerificationQueueError);
});

test("queue outage cannot be acknowledged as success", async () => {
  const queue = new ServerVerificationQueueV1(
    "https://mytest.supabase.co",
    "mock-service-key-long-enough",
    (async () => new Response("unavailable", { status: 503 })) as typeof fetch,
  );
  await assert.rejects(
    queue.enqueue(ORG, BOUNTY, ATTEMPT, MANIFEST, "review"),
    VerificationQueueError,
  );
});
