import assert from "node:assert/strict";
import test from "node:test";
import { PROTOCOL_NAME, SPECIFICATION_STATUS } from "../src/index.js";
test("shared package cannot misrepresent product readiness", () => {
  assert.equal(PROTOCOL_NAME, "CertiFiks");
  assert.equal(SPECIFICATION_STATUS, "unverified");
});
