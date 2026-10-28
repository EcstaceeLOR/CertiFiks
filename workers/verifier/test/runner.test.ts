import assert from "node:assert/strict";
import { mkdir, mkdtemp, realpath, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  classifyContainerExitCode,
  resolveTrustedCheckoutWorkspace,
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

test("rejects absolute and alternative shell entrypoints before Docker", async () => {
  for (const executable of [
    "/bin/sh",
    "/usr/bin/bash",
    "/bin/dash",
    "/bin/ash",
    "C:\\Windows\\System32\\cmd.exe",
    "/usr/bin/pwsh",
  ]) {
    await assert.rejects(
      runUntrustedCode({
        workspace: ".",
        image: pinnedImage,
        command: [executable, "-c", "echo unsafe"],
      }),
      /SANDBOX_SHELL_ENTRYPOINT_FORBIDDEN/,
    );
  }
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

test("trusted checkout root admits its child but refuses root, host and symlink escapes", async () => {
  const root = await mkdtemp(join(tmpdir(), "certifiks-trusted-checkouts-"));
  const external = await mkdtemp(join(tmpdir(), "certifiks-external-host-"));
  const work = join(root, "attempt-a");
  try {
    await mkdir(work);
    await symlink(external, join(root, "stolen-host"));
    assert.equal(
      await resolveTrustedCheckoutWorkspace(work, root),
      await realpath(work),
    );
    for (const [requested, allowedRoot] of [
      [work, undefined],
      [work, "."],
      [work, "/"],
      [root, root],
      [external, root],
      [join(root, "stolen-host"), root],
    ] as const) {
      await assert.rejects(
        resolveTrustedCheckoutWorkspace(requested, allowedRoot),
        /SANDBOX_(CHECKOUT_ROOT_UNCONFIGURED|WORKSPACE_OUTSIDE_TRUSTED_ROOT)/,
      );
    }
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(external, { recursive: true, force: true });
  }
});

test("Docker, OOM, and signal failures can never masquerade as a failed baseline test", () => {
  for (const code of [0, 124, 125, 126, 127, 137, 143, -1, 1.5]) {
    assert.equal(classifyContainerExitCode(code), "runner_error");
  }
  for (const code of [1, 2, 42]) {
    assert.equal(classifyContainerExitCode(code), "failed");
  }
});
