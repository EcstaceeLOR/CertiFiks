import assert from "node:assert/strict";
import test from "node:test";
import { buildApp } from "../src/app.js";

const supabaseUrl = "https://certifiks-ci.supabase.co";
const supabaseServiceRoleKey = "synthetic-ci-key-not-a-real-credential";
const webhookSecret = "synthetic-webhook-secret-not-a-real-credential";

test("unconfigured transport is not ready", async () => {
  const app = buildApp({
    production: true,
    webhookJournalDirectory: "/tmp/not-durable",
    publicBountyFetch: async () => {
      throw new Error("unconfigured instance must never probe");
    },
  });
  try {
    const response = await app.inject({ method: "GET", url: "/readyz" });
    assert.equal(response.statusCode, 503);
    assert.equal(response.headers["cache-control"], "no-store");
    assert.deepEqual(response.json(), {
      status: "not_ready",
      transportReady: false,
      productReady: false,
      settlementReady: false,
      checks: { publicProjection: "not_checked", webhookJournal: "blocked" },
    });
    const live = await app.inject({ method: "GET", url: "/health" });
    assert.equal(live.statusCode, 200);
    assert.equal(live.json().productReady, false);
  } finally {
    await app.close();
  }
});

test("authorized public projection determines readiness", async () => {
  let calls = 0;
  const app = buildApp({
    production: true,
    webhookSecret,
    supabaseUrl,
    supabaseServiceRoleKey,
    publicBountyFetch: async (input, init) => {
      calls += 1;
      const target = new URL(String(input));
      assert.equal(target.protocol, "https:");
      assert.equal(target.hostname, "certifiks-ci.supabase.co");
      assert.equal(target.pathname, "/rest/v1/certifiks_public_bounties_v1");
      assert.equal(target.searchParams.get("limit"), "1");
      assert.equal(init?.method, "GET");
      assert.equal(init?.redirect, "error");
      const headers = init?.headers as Record<string, string> | undefined;
      assert.equal(headers?.apikey, supabaseServiceRoleKey);
      return new Response("[]", { status: 200 });
    },
  });
  try {
    const response = await app.inject({ method: "GET", url: "/readyz" });
    assert.equal(response.statusCode, 200);
    assert.deepEqual(response.json(), {
      status: "ready",
      transportReady: true,
      productReady: false,
      settlementReady: false,
      checks: { publicProjection: "reachable", webhookJournal: "configured" },
    });
    assert.equal(calls, 1);
    assert.ok(!response.body.includes(supabaseServiceRoleKey));
  } finally {
    await app.close();
  }
});

test("upstream faults do not leak internal details", async () => {
  for (const request of [
    async () => {
      throw new Error(
        `private-provider-error with secret ${supabaseServiceRoleKey}`,
      );
    },
    async () => new Response("access denied", { status: 401 }),
    async () => new Response('{"private":"tenant-data"}', { status: 200 }),
  ]) {
    const app = buildApp({
      production: true,
      webhookSecret,
      supabaseUrl,
      supabaseServiceRoleKey,
      publicBountyFetch: request,
    });
    try {
      const response = await app.inject({ method: "GET", url: "/readyz" });
      assert.equal(response.statusCode, 503);
      assert.equal(response.json().checks.publicProjection, "unavailable");
      assert.equal(response.json().productReady, false);
      assert.ok(!response.body.includes("private"));
      assert.ok(!response.body.includes(supabaseServiceRoleKey));
      assert.ok(!response.body.includes("provider"));
    } finally {
      await app.close();
    }
  }
});

test("invalid destinations and missing secrets block readiness", async () => {
  for (const config of [
    { supabaseUrl: "http://127.0.0.1:5432", webhookSecret },
    { supabaseUrl, webhookSecret: "" },
  ]) {
    const app = buildApp({
      production: true,
      supabaseServiceRoleKey,
      ...config,
      publicBountyFetch: async () => {
        throw new Error("wrong endpoint should not succeed");
      },
    });
    try {
      const response = await app.inject({ method: "GET", url: "/readyz" });
      assert.equal(response.statusCode, 503);
      assert.equal(response.json().transportReady, false);
    } finally {
      await app.close();
    }
  }
});
