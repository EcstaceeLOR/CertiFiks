import assert from "node:assert/strict";
import test from "node:test";
import {
  ServerSponsorFundingIntentV1,
  SponsorFundingIntentError,
} from "../src/bounties/sponsor-intent.js";

const org = "20000000-0000-4000-8000-000000000001";
const bounty = "30000000-0000-4000-8000-000000000002";
const user = "10000000-0000-4000-8000-000000000001";
const intentId = "80000000-0000-4000-8000-000000000001";
const principal = {
  authenticatedUserId: user,
  authenticatedOrganizationId: org,
  sponsorAuthorized: true,
};
const details = {
  bountyId: bounty,
  manifestDigest: "0x" + "a".repeat(64),
  chainId: "11155111",
  rewardAtoms: "9007199254740993123456789000",
  idempotencyDigest: "b".repeat(64),
};

test("frozen funding intent uses authenticated identities, exact atomic units, and never asserts money moved", async () => {
  let count = 0;
  const query = (async (url: string, opts?: RequestInit) => {
    count++;
    assert.equal(url,
      "https://funding-demo.supabase.co/rest/v1/rpc/certifiks_prepare_sponsor_funding");
    assert.equal(opts?.redirect, "error");
    assert.equal(new Headers(opts?.headers).get("Authorization"),
      "Bearer server-key-test-only-very-long");
    const args = JSON.parse(String(opts?.body));
    assert.deepEqual(args, {
      p_org: org,
      p_bounty: bounty,
      p_actor: user,
      p_manifest: details.manifestDigest,
      p_chain: details.chainId,
      p_reward: details.rewardAtoms,
      p_idempotency_digest: details.idempotencyDigest,
    });
    return new Response(JSON.stringify(intentId), { status: 200 });
  }) as typeof fetch;
  const client = new ServerSponsorFundingIntentV1(
    "https://funding-demo.supabase.co", "server-key-test-only-very-long", query,
  );
  const receipt = await client.prepare(principal, details);
  assert.deepEqual(receipt, {
    intentId, state: "prepared", walletSigned: false,
    fundingConfirmed: false, payoutAuthorized: false,
  });
  assert.equal(count, 1);
});

test("missing sponsor session, invalid manifest or unsafe Javascript numeric formats never call server", async () => {
  let calls = 0;
  const stub = (async () => {
    calls++;
    return new Response(JSON.stringify(intentId), { status: 200 });
  }) as typeof fetch;
  const client = new ServerSponsorFundingIntentV1(
    "https://funding-demo.supabase.co", "server-key-test-only-very-long", stub,
  );
  await assert.rejects(client.prepare(
    { ...principal, sponsorAuthorized: false }, details,
  ), SponsorFundingIntentError);
  await assert.rejects(client.prepare(principal, {
    ...details, rewardAtoms: "1.5",
  }), SponsorFundingIntentError);
  await assert.rejects(client.prepare(principal, {
    ...details, chainId: "01",
  }), SponsorFundingIntentError);
  await assert.rejects(client.prepare(principal, {
    ...details, manifestDigest: "fake-acceptance",
  }), SponsorFundingIntentError);
  assert.equal(calls, 0);
});

test("backend errors cannot create false submitted or funded wallet receipts", async () => {
  const stub = (async () => new Response("backend rejected", {
    status: 403,
  })) as typeof fetch;
  const client = new ServerSponsorFundingIntentV1(
    "https://funding-demo.supabase.co", "server-key-test-only-very-long", stub,
  );
  await assert.rejects(client.prepare(principal, details),
    SponsorFundingIntentError);
});

test("cancellation requires original authenticated sponsor and tenant", async () => {
  let invoked = 0;
  const stub = (async (url: string, opts?: RequestInit) => {
    invoked++;
    assert.equal(url,
      "https://funding-demo.supabase.co/rest/v1/rpc/certifiks_cancel_sponsor_funding");
    assert.deepEqual(JSON.parse(String(opts?.body)), {
      p_intent: intentId, p_org: org, p_actor: user,
    });
    return new Response(JSON.stringify(true), { status: 200 });
  }) as typeof fetch;
  const client = new ServerSponsorFundingIntentV1(
    "https://funding-demo.supabase.co", "server-key-test-only-very-long", stub,
  );
  await assert.rejects(client.cancel({
    ...principal, sponsorAuthorized: false,
  }, intentId), SponsorFundingIntentError);
  assert.equal(invoked, 0);
  assert.equal(await client.cancel(principal, intentId), true);
  assert.equal(invoked, 1);
});
