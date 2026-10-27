import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import test from "node:test";
import {
  canonicalReviewJson,
  SecurityReleaseBlockedError,
  verifyIndependentSecurityReviewV1,
} from "./independent-review-gate.mjs";

const RELEASE_SHA = "a".repeat(40);
const REVIEWER = "independent-audit-org";
const privateAndPublic = generateKeyPairSync("ed25519");
const pem = privateAndPublic.publicKey
  .export({ format: "pem", type: "spki" })
  .toString();
const validReview = () => ({
  version: "1",
  releaseCommit: RELEASE_SHA,
  reviewerOrganizationId: REVIEWER,
  reviewedAt: "2026-10-26T18:30:00.000Z",
  scopes: [
    "smart_contracts",
    "github_auth_and_webhooks",
    "api_tenant_boundaries",
    "verifier_sandbox",
    "wallet_and_settlement",
    "artifact_access",
  ],
  findings: [
    {
      findingId: "CVE-review-0001",
      severity: "high",
      status: "remediated_retested",
      retestEvidenceSha256: "b".repeat(64),
    },
  ],
  sourceArchiveSha256: "c".repeat(64),
  sbomSha256: "d".repeat(64),
  testRunSha256: "e".repeat(64),
  reviewMethodologyUrl: "https://github.com/EcstaceeLOR/CertiFiks/issues/41",
  independentRetestUrl: "https://github.com/EcstaceeLOR/CertiFiks/issues/41",
});
function signed(report = validReview()) {
  const bytes = Buffer.from(canonicalReviewJson(report), "utf8");
  const signature = sign(null, bytes, privateAndPublic.privateKey).toString(
    "base64",
  );
  return [bytes, signature];
}

test("synthetic signed reviewer report is NEVER a production-approval certificate", () => {
  const result = verifyIndependentSecurityReviewV1(
    ...signed(),
    pem,
    RELEASE_SHA,
    REVIEWER,
  );
  assert.equal(result.verifiedReviewerSignature, true);
  assert.equal(result.unresolvedCriticalOrHigh, false);
  assert.equal(result.productionApproved, false);
});

test("a byte-tampered audit or wrong trusted key cannot authenticate", () => {
  const [bytes, signature] = signed();
  const tampered = Buffer.from(bytes);
  const idx = tampered.indexOf("remediated_retested");
  assert.ok(idx > 0);
  tampered[idx] ^= 1;
  assert.throws(
    () =>
      verifyIndependentSecurityReviewV1(
        tampered,
        signature,
        pem,
        RELEASE_SHA,
        REVIEWER,
      ),
    SecurityReleaseBlockedError,
  );
  const impostor = generateKeyPairSync("ed25519");
  const otherPublicKey = impostor.publicKey
    .export({ format: "pem", type: "spki" })
    .toString();
  assert.throws(
    () =>
      verifyIndependentSecurityReviewV1(
        bytes,
        signature,
        otherPublicKey,
        RELEASE_SHA,
        REVIEWER,
      ),
    SecurityReleaseBlockedError,
  );
});

test("wrong release SHA or independent reviewer identity fails closed", () => {
  const [bytes, signature] = signed();
  assert.throws(
    () =>
      verifyIndependentSecurityReviewV1(
        bytes,
        signature,
        pem,
        "f".repeat(40),
        REVIEWER,
      ),
    /release or independent organization/,
  );
  assert.throws(
    () =>
      verifyIndependentSecurityReviewV1(
        bytes,
        signature,
        pem,
        RELEASE_SHA,
        "self-review-org",
      ),
    /release or independent organization/,
  );
});

test("unresolved critical or high findings reject even an authentically signed report", () => {
  for (const [severity, status, evidence] of [
    ["critical", "unresolved", null],
    ["high", "risk_accepted", "b".repeat(64)],
    ["high", "remediated_retested", null],
  ]) {
    const report = validReview();
    report.findings[0] = {
      findingId: "CVE-review-0001",
      severity,
      status,
      retestEvidenceSha256: evidence,
    };
    assert.throws(
      () =>
        verifyIndependentSecurityReviewV1(
          ...signed(report),
          pem,
          RELEASE_SHA,
          REVIEWER,
        ),
      /independent retest/,
    );
  }
});

test("missing attack surface or dummy reviewer evidence is not a valid audit", () => {
  const missing = validReview();
  missing.scopes.pop();
  assert.throws(
    () =>
      verifyIndependentSecurityReviewV1(
        ...signed(missing),
        pem,
        RELEASE_SHA,
        REVIEWER,
      ),
    /omits required attack surface/,
  );
  const fake = validReview();
  fake.independentRetestUrl = "https://example.com/security-review.pdf";
  assert.throws(
    () =>
      verifyIndependentSecurityReviewV1(
        ...signed(fake),
        pem,
        RELEASE_SHA,
        REVIEWER,
      ),
    /non-placeholder HTTPS/,
  );
});
