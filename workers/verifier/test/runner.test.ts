import assert from "node:assert/strict";
import test from "node:test";
import {
  runUntrustedCode,
  verifierAvailable,
  verifierLimits,
} from "../src/index.js";

const pinnedImage = `registry.example/runner@sha256:${"a".repeat(64)}`;

test("runner is enabled but exposes strict resource and network limits", () => {
  assert.equal(verifierAvailable, true);
  assert.equal(verifierLimits.network, "disabled");
  assert.equal(verifierLimits.workspace, "read-only");
  assert.equal(verifierLimits.maxTimeoutMs, 600_000);
});

test("rejects mutable image tags before starting Docker", async () => {
  await assert.rejects(
    runUntrustedCode({
      workspace: ".",
      image: "node:latest",
      command: ["node", "--version"],
    }),
    /SANDBOX_IMAGE_MUST_BE_DIGEST_PINNED/,
  );
});

test("rejects shell entrypoints to prevent implicit shell evaluation", async () => {
  await assert.rejects(
    runUntrustedCode({
      workspace: ".",
      image: pinnedImage,
      command: ["sh", "-c", "echo unsafe"],
    }),
    /SANDBOX_SHELL_ENTRYPOINT_FORBIDDEN/,
  );
});

test("rejects timeout values outside the policy range", async () => {
  await assert.rejects(
    runUntrustedCode({
      workspace: ".",
      image: pinnedImage,
      command: ["node", "--version"],
      timeoutMs: 999_999,
    }),
    /SANDBOX_TIMEOUT_OUT_OF_RANGE/,
  );
});
