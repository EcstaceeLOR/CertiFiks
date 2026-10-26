import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import canonicalize from "canonicalize";

const manifestVector = JSON.parse(
  await readFile(
    new URL("../protocol/vectors/manifest-v1.json", import.meta.url),
  ),
);
function run(path, digest) {
  return spawnSync(
    process.execPath,
    [
      "--import",
      "tsx",
      "scripts/verify-manifest.mjs",
      path,
      "--expected-digest",
      digest,
    ],
    { encoding: "utf8", timeout: 15000 },
  );
}

test("independent CLI verifies the committed protocol golden manifest", async () => {
  const dir = await mkdtemp(join(tmpdir(), "certifiks-manifest-cli-"));
  try {
    const path = join(dir, "manifest.json");
    await writeFile(path, canonicalize(manifestVector.input));
    const output = run(path, manifestVector.expected);
    assert.equal(output.status, 0, output.stderr);
    const result = JSON.parse(output.stdout);
    assert.equal(result.manifestDigest, manifestVector.expected);
    assert.equal(result.matchedTrustedCommitment, true);
    assert.equal(result.fundingVerifiedByCli, false);
    assert.ok(!output.stdout.includes("privateKey"));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("modified reward, uncanonical bytes and attacker-provided wrong digest fail closed", async () => {
  const dir = await mkdtemp(join(tmpdir(), "certifiks-manifest-cli-"));
  try {
    const path = join(dir, "manifest.json");
    const tampered = structuredClone(manifestVector.input);
    tampered.reward.amountAtoms = "100000000000001";
    await writeFile(path, canonicalize(tampered));
    let result = run(path, manifestVector.expected);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /MANIFEST_REJECTED/);
    await writeFile(path, JSON.stringify(manifestVector.input, null, 2));
    result = run(path, manifestVector.expected);
    assert.equal(result.status, 1);
    await writeFile(path, canonicalize(manifestVector.input));
    result = run(path, "0x" + "a".repeat(64));
    assert.equal(result.status, 1);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("CLI refuses implicit or malformed trusted commitment argument", async () => {
  const result = spawnSync(
    process.execPath,
    ["--import", "tsx", "scripts/verify-manifest.mjs", "manifest.json"],
    { encoding: "utf8", timeout: 15000 },
  );
  assert.equal(result.status, 2);
  assert.match(result.stderr, /--expected-digest/);
});
