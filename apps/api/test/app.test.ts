import assert from "node:assert/strict";
import test from "node:test";
import { buildApp } from "../src/app.js";

test("health reports accurate transport-only readiness", async () => {
  const app = buildApp();
  try {
    const response = await app.inject({ method: "GET", url: "/health" });
    assert.equal(response.statusCode, 200);
    const json = response.json();
    assert.equal(json.status, "ok");
    assert.equal(json.productReady, false);
  } finally {
    await app.close();
  }
});


test("production refuses filesystem-only webhook persistence", async () => {
  const app = buildApp({
    production: true,
    webhookSecret: "sample-long-webhook-secret-with-minimum-entropy",
    webhookJournalDirectory: "/tmp/not-a-durable-production-volume",
  });
  try {
    const health = await app.inject({ method: "GET", url: "/health" });
    assert.equal(health.json().webhookIngestionConfigured, false);
    const webhook = await app.inject({
      method: "POST",
      url: "/webhooks/github",
      headers: { "content-type": "application/json" },
      payload: "{}",
    });
    assert.equal(webhook.statusCode, 503);
  } finally {
    await app.close();
  }
});
