import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  assembleEvidenceBundleV1,
  createEvidenceReportV1,
  signEvidenceReportV1,
} from "../packages/shared/src/evidence-report.ts";

const files = {
  "baseline-log": Buffer.from("baseline FAILED: exact pinned test\n", "utf8"),
  "candidate-log": Buffer.from("candidate PASSED: local test fixture only\n", "utf8"),
  "regression-log": Buffer.from("regression PASSED: local test fixture only\n", "utf8"),
};

function launch(bundlePath, rosterPath, artifactDir) {
  return spawnSync(
    process.execPath,
    ["--import", "tsx", "scripts/verify-evidence.mjs", bundlePath, rosterPath, artifactDir],
    { encoding: "utf8", timeout: 15000 },
  );
}

test("downloaded signed report verifies with independently provisioned enrolled signer roster and private logs", async () => {
  const dir = await mkdtemp(join(tmpdir(), "certifiks-signed-cli-"));
  try {
    const artifactDir = join(dir, "artifacts");
    await mkdir(artifactDir);
    for (const [role, bytes] of Object.entries(files)) {
      await writeFile(join(artifactDir, role + ".bin"), bytes);
    }
    const signed = [generateKeyPairSync("ed25519"), generateKeyPairSync("ed25519")];
    const signers = signed.map((pair, i) => ({
      keyId: "key-" + String(i + 1),
      organizationId: "independent-org-" + String(i + 1),
      privateKeyPem: pair.privateKey.export({ format: "pem", type: "pkcs8" }).toString(),
    }));
    const roster = signed.map((pair, i) => ({
      keyId: signers[i].keyId,
      organizationId: signers[i].organizationId,
      publicKeyPem: pair.publicKey.export({ format: "pem", type: "spki" }).toString(),
    }));
    const report = createEvidenceReportV1(
      {
        repositoryId: "123456",
        bountyId: "42",
        attemptId: "1",
        manifestDigest: "0x" + "a".repeat(64),
        imageDigest: "0x" + "b".repeat(64),
        baseCommitSha: "c".repeat(40),
        headCommitSha: "d".repeat(40),
        testPlanDigest: "0x" + "e".repeat(64),
        runnerResultDigest: "0x" + "f".repeat(64),
        createdAt: "2026-10-26T10:00:00.000Z",
        reportedDecision: "qualified",
      },
      files,
    );
    const bundle = assembleEvidenceBundleV1(
      report,
      signers.map((signer) => signEvidenceReportV1(report, signer)),
    );
    const bundlePath = join(dir, "bundle.json");
    const rosterPath = join(dir, "trusted-roster.json");
    await writeFile(bundlePath, JSON.stringify(bundle));
    await writeFile(rosterPath, JSON.stringify(roster));
    let response = launch(bundlePath, rosterPath, artifactDir);
    assert.equal(response.status, 0, response.stderr);
    let outcome = JSON.parse(response.stdout);
    assert.equal(outcome.integrity, "verified");
    assert.equal(outcome.reportedDecision, "qualified");
    assert.equal(outcome.payoutAuthorized, false);

    await writeFile(join(artifactDir, "candidate-log.bin"), Buffer.from("MALICIOUS TEST REPLACEMENT"));
    response = launch(bundlePath, rosterPath, artifactDir);
    assert.equal(response.status, 1);
    assert.match(response.stderr, /EVIDENCE_REJECTED/);

    await writeFile(join(artifactDir, "candidate-log.bin"), files["candidate-log"]);
    await writeFile(rosterPath, JSON.stringify([{ ...roster[0], revoked: true }, roster[1]]));
    response = launch(bundlePath, rosterPath, artifactDir);
    assert.equal(response.status, 1);
    assert.ok(!response.stdout.includes("verified"));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
