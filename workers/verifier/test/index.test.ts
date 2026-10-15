import assert from "node:assert/strict";
import test from "node:test";
import { runUntrustedCode, verifierAvailable } from "../src/index.js";

test("verifier runner is available after isolated runner implementation", () => {
  assert.equal(verifierAvailable, true);
});

test("verifier rejects an unpinned image before attempting execution", async () => {
  await assert.rejects(
    runUntrustedCode({
      workspace: ".",
      image: "node:latest",
      command: ["node", "--version"],
    }),
    /SANDBOX_IMAGE_MUST_BE_DIGEST_PINNED/,
  );
});
