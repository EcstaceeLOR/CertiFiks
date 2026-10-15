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
