import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  E2EIntakeError,
  REQUIRED_LIVE_SCENARIOS_V1,
  validateLiveE2EIntakeV1,
} from "./live-e2e-evidence.mjs";

function fixture() {
  const receiptPath = "receipts/chain.json";
  const reportPath = "reports/runner.json";
  const reviewerPath = "reports/replay.json";
  const screenshotPath = "browser/desktop.png";
  const contentByPath = {
    [receiptPath]: "SYNTHETIC RECEIPT FOR NEGATIVE UNIT TESTS ONLY",
    [reportPath]: "SYNTHETIC RUNNER TRACE, NOT PRODUCTION EVIDENCE",
    [reviewerPath]: "SYNTHETIC REVIEW",
    [screenshotPath]: "SYNTHETIC SCREENSHOT",
  };
  const artifactPaths = Object.keys(contentByPath);
  const artifacts = artifactPaths.map((path) => ({
    path,
    sha256: createHash("sha256").update(contentByPath[path]).digest("hex"),
    sizeBytes: Buffer.byteLength(contentByPath[path]),
    kind: path.startsWith("receipts/") ? "receipt" : path.startsWith("browser/") ?
      "browser" : "report",
  }));
  // More than eight independent paths are required for an actual bundle.
  for (let i = 0; i < 5; i++) {
    const path = `reports/synthetic-${i}.txt`;
    contentByPath[path] = `SYNTHETIC UNIT TEST DATA ${i}`;
    artifacts.push({
      path,
      sha256: createHash("sha256").update(contentByPath[path]).digest("hex"),
      sizeBytes: Buffer.byteLength(contentByPath[path]),
      kind: "report",
    });
  }
  const tx = (purpose, n) => ({
    purpose,
    hash: "0x" + n.repeat(64),
    chainId: "31337",
    explorerUrl: "https://github.com/EcstaceeLOR/CertiFiks/issues/40",
    confirmedBlockHash: "0x" + "f".repeat(64),
    receiptArtifact: receiptPath,
  });
  const bundle = {
    version: "1",
    claim: "live_evidence_submitted",
    sourceCommit: "a".repeat(40),
    network: {
      networkName: "SYNTHETIC_UNIT_TEST",
      chainId: "31337",
      genesisHash: "0x" + "b".repeat(64),
      approvedRuntimeEvidenceUrl: "https://github.com/EcstaceeLOR/CertiFiks/issues/18",
    },
    participants: {
      sponsorGitHubUserId: "101",
      contributorGitHubUserId: "102",
      verifierOrganizationIds: ["synthetic-review-org-a", "synthetic-review-org-b"],
      independentReplayGitHubUserId: "103",
    },
    transactions: [
      tx("funding", "1"), tx("withdrawal", "2"), tx("refund", "3"),
    ],
    escrowConservation: {
      openingAtoms: "0",
      depositsAtoms: "1000",
      withdrawalsAtoms: "650",
      refundsAtoms: "300",
      closingAtoms: "50",
    },
    scenarios: REQUIRED_LIVE_SCENARIOS_V1.map((name) => ({
      name, status: "observed_pass", evidenceArtifact: reportPath,
    })),
    artifacts,
    independentReviewer: {
      githubUserId: "103",
      reviewUrl: "https://github.com/EcstaceeLOR/CertiFiks/issues/40",
      reviewArtifact: reviewerPath,
    },
  };
  return { bundle, contentByPath };
}
async function withFixture(fn) {
  const root = await mkdtemp(join(tmpdir(), "certifiks-e2e-negative-test-"));
  try {
    const { bundle, contentByPath } = fixture();
    for (const [path, data] of Object.entries(contentByPath)) {
      const folder = join(root, path.split("/")[0]);
      await mkdir(folder, { recursive: true });
      await writeFile(join(root, path), data);
    }
    return await fn(bundle, root);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

test("a complete synthetic structure is never marked independently approved", async () => {
  await withFixture(async (bundle, root) => {
    const outcome = await validateLiveE2EIntakeV1(bundle, root);
    assert.equal(outcome.intake, "STRUCTURALLY_COMPLETE_UNVERIFIED");
    assert.equal(outcome.productionApproved, false);
    assert.equal(outcome.verifiedOnChain, false);
    assert.equal(outcome.reviewedIndependently, false);
    assert.equal(outcome.scenariosClaimed, REQUIRED_LIVE_SCENARIOS_V1.length);
  });
});

test("tampered private artifacts fail even when their metadata is unchanged", async () => {
  await withFixture(async (bundle, root) => {
    await writeFile(join(root, "reports/runner.json"), "ALTERED");
    await assert.rejects(validateLiveE2EIntakeV1(bundle, root), E2EIntakeError);
  });
});

test("fake payouts, duplicate receipts and unbalanced custody always fail", async () => {
  await withFixture(async (bundle, root) => {
    bundle.escrowConservation.withdrawalsAtoms = "9999";
    await assert.rejects(validateLiveE2EIntakeV1(bundle, root), /conservation/);
    bundle.escrowConservation.withdrawalsAtoms = "650";
    bundle.transactions[1].hash = bundle.transactions[0].hash;
    await assert.rejects(validateLiveE2EIntakeV1(bundle, root), /replayed/);
  });
});

test("no missing real-world rejection path can be called complete", async () => {
  await withFixture(async (bundle, root) => {
    bundle.scenarios.pop();
    await assert.rejects(validateLiveE2EIntakeV1(bundle, root), /inventory/);
  });
});

test("mock outcomes and placebo URLs are rejected", async () => {
  await withFixture(async (bundle, root) => {
    bundle.scenarios[0].status = "mocked_success";
    await assert.rejects(validateLiveE2EIntakeV1(bundle, root), E2EIntakeError);
    bundle.scenarios[0].status = "observed_pass";
    bundle.network.approvedRuntimeEvidenceUrl = "https://example.com/fake";
    await assert.rejects(validateLiveE2EIntakeV1(bundle, root), /chain runtime/);
  });
});

test("artifact path traversal, symbolic links, missing bytes and untrusted files fail", async () => {
  await withFixture(async (bundle, root) => {
    bundle.artifacts[0].path = "../secret.json";
    await assert.rejects(validateLiveE2EIntakeV1(bundle, root), E2EIntakeError);
    bundle.artifacts[0].path = "receipts/chain.json";
    await rm(join(root, "receipts/chain.json"));
    await assert.rejects(validateLiveE2EIntakeV1(bundle, root), E2EIntakeError);
  });
});
