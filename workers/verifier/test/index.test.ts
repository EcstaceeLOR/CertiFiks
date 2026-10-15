import assert from "node:assert/strict";
import test from "node:test";
import { runUntrustedCode, verifierAvailable } from "../src/index.js";
test("unimplemented verifier cannot report a false success", () => {
  assert.equal(verifierAvailable, false);
  assert.throws(() => runUntrustedCode(), /VERIFIER_DISABLED/);
});
