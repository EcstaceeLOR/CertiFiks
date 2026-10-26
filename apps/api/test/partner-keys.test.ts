import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { buildApp } from "../src/app.js";

const API_KEY = "cfk_" + "A".repeat(43);
const SERVICE = "private-server-service-key-never-expose";
const BOUNTY_ID = "30000000-0000-4000-8000-000000000001";
const ROW = {
  bounty_id: BOUNTY_ID,
  repository_id: "321",
  repository_full_name: "open/real-repo",
  chain_id: "11155111",
  onchain_bounty_id: "7",
  reward_atoms: "9007199254740993123456789",
  manifest_digest: "0x" + "a".repeat(64),
  state: "funded",
  created_at: "2026-10-26T12:00:00.000Z",
};

test("scoped token requires transactional DB authorization and preserves precise public values", async () => {
  const authCalls: string[] = [];
  const publicCalls: string[] = [];
  const app = buildApp({
    supabaseUrl: "https://test-pub.supabase.co",
    supabaseServiceRoleKey: SERVICE,
    partnerAuthorizationFetch: (async (url: string, init?: RequestInit) => {
      assert.equal(String(url), "https://test-pub.supabase.co/rest/v1/rpc/certifiks_authorize_partner_key");
      assert.equal(init?.redirect, "error");
      const payload = JSON.parse(String(init?.body));
      authCalls.push(payload.p_sha256);
      assert.equal(payload.p_sha256, createHash("sha256").update(API_KEY).digest("hex"));
      assert.equal(payload.p_scope, "bounties:read");
      assert.equal(JSON.stringify(payload).includes(API_KEY), false);
      return new Response("true", { status: 200 });
    }) as typeof fetch,
    publicBountyFetch: (async (url: string, options?: RequestInit) => {
      publicCalls.push(String(url));
      assert.equal(options?.method, "GET");
      return new Response(JSON.stringify([ROW]), { status: 200 });
    }) as typeof fetch,
  });
  try {
    const reply = await app.inject({
      method: "GET",
      url: "/v1/partner/bounties?limit=5&offset=0&state=funded&repo=open%2Freal-repo&sort=oldest",
      headers: { "x-certifiks-api-key": API_KEY },
    });
    assert.equal(reply.statusCode, 200, reply.body);
    assert.equal(reply.headers["cache-control"], "no-store");
    const json = reply.json();
    assert.equal(json.items[0].rewardAtoms, ROW.reward_atoms);
    assert.equal(json.items[0].verificationProven, false);
    assert.equal(json.verificationProven, false);
    assert.equal(json.page.offset, 0);
    assert.equal(authCalls.length, 1);
    assert.equal(publicCalls.length, 1);
    assert.ok(publicCalls[0].includes("order=created_at.asc"));
    assert.ok(!reply.body.includes(SERVICE));
    assert.ok(!reply.body.includes(API_KEY));
  } finally {
    await app.close();
  }
});

test("absent/malformed tokens and revoked DB access never read bounty records", async () => {
  let authorized = 0;
  let fetched = 0;
  const app = buildApp({
    supabaseUrl: "https://test-pub.supabase.co",
    supabaseServiceRoleKey: SERVICE,
    partnerAuthorizationFetch: (async () => {
      authorized++;
      return new Response("false", { status: 200 });
    }) as typeof fetch,
    publicBountyFetch: (async () => {
      fetched++;
      throw new Error("must not read public data");
    }) as typeof fetch,
  });
  try {
    for (const headers of [
      {},
      { "x-certifiks-api-key": "forged" },
      { "x-certifiks-api-key": API_KEY },
    ]) {
      const reply = await app.inject({
        method: "GET",
        url: "/v1/partner/bounties",
        headers,
      });
      assert.equal(reply.statusCode, 401);
    }
    assert.equal(authorized, 1);
    assert.equal(fetched, 0);
  } finally {
    await app.close();
  }
});

test("service outage fails closed and strict filters reject injection after auth", async () => {
  let fetched = 0;
  const app = buildApp({
    supabaseUrl: "https://test-pub.supabase.co",
    supabaseServiceRoleKey: SERVICE,
    partnerAuthorizationFetch: (async () => new Response("true", { status: 200 })) as typeof fetch,
    publicBountyFetch: (async () => {
      fetched++;
      return new Response("[]", { status: 200 });
    }) as typeof fetch,
  });
  try {
    for (const url of [
      "/v1/partner/bounties?sort=__proto__",
      "/v1/partner/bounties?limit=999",
      "/v1/partner/bounties?offset=-5",
      "/v1/partner/bounties?repo=evil%2Fname%3Fselect%3D*",
      "/v1/partner/bounties?private=true",
    ]) {
      const reply = await app.inject({ method: "GET", url, headers: { "x-certifiks-api-key": API_KEY } });
      assert.equal(reply.statusCode, 400, url);
    }
    assert.equal(fetched, 0);
  } finally {
    await app.close();
  }
  const outage = buildApp({
    supabaseUrl: "https://test-pub.supabase.co",
    supabaseServiceRoleKey: SERVICE,
    partnerAuthorizationFetch: (async () => new Response("unavailable", { status: 503 })) as typeof fetch,
  });
  try {
    const reply = await outage.inject({
      method: "GET",
      url: "/v1/partner/bounties",
      headers: { "x-certifiks-api-key": API_KEY },
    });
    assert.equal(reply.statusCode, 503);
  } finally {
    await outage.close();
  }
});
