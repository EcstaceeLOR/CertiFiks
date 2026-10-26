import { createHash, randomBytes } from "node:crypto";

/**
 * Domain-separated blinding envelope only. A SHA-256 commitment is NOT a
 * signature, signed vote, independent quorum or authorization to pay.
 * Caller MUST verify actor-session identity and explicit review consent.
 */
const UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const DIGEST = /^0x[a-f0-9]{64}$/;
const SHA = /^[a-f0-9]{40}$/;
const KEY = /^[A-Za-z0-9_-]{3,80}$/;
const DOMAIN = "CertiFiks:independent-review-blind-v1\0";

export type PrivateReviewerDecisionV1 = "approve" | "reject" | "inconclusive";

export interface PrivateReviewerCommitmentV1 {
  caseOrganizationId: string;
  runId: string;
  reviewerUserId: string;
  signerOrganizationId: string;
  signerKeyId: string;
  headCommitSha: string;
  fundedManifestDigest: string;
  runnerResultDigest: string;
  signedReportDigest: string;
  decision: PrivateReviewerDecisionV1;
}

export function makeReviewerNonceV1(): Uint8Array {
  return randomBytes(32);
}

export function computeBlindReviewerCommitmentV1(
  value: PrivateReviewerCommitmentV1,
  secretNonce: Uint8Array,
): { commitmentDigest: string; signed: false; onchainAttested: false } {
  if (
    !value ||
    [value.caseOrganizationId, value.runId, value.reviewerUserId,
      value.signerOrganizationId].some((id) => typeof id !== "string" || !UUID.test(id)) ||
    typeof value.signerKeyId !== "string" || !KEY.test(value.signerKeyId) ||
    typeof value.headCommitSha !== "string" || !SHA.test(value.headCommitSha) ||
    [value.fundedManifestDigest, value.runnerResultDigest, value.signedReportDigest]
      .some((d) => typeof d !== "string" || !DIGEST.test(d)) ||
    !["approve", "reject", "inconclusive"].includes(value.decision) ||
    !(secretNonce instanceof Uint8Array) || secretNonce.length !== 32
  ) {
    throw new TypeError("Invalid bounded private reviewer proof context or nonce");
  }

  // Strict field ordering, explicit domain and fixed-length nonce. Hashing
  // never publishes the decision, signed key or secret preimage to the DB.
  const parts = [
    value.caseOrganizationId, value.runId,
    value.reviewerUserId, value.signerOrganizationId, value.signerKeyId,
    value.headCommitSha, value.fundedManifestDigest, value.runnerResultDigest,
    value.signedReportDigest, value.decision,
    Buffer.from(secretNonce).toString("hex"),
  ];
  const hash = createHash("sha256");
  hash.update(DOMAIN);
  for (const part of parts) {
    hash.update(String(Buffer.byteLength(part, "utf8")));
    hash.update(":");
    hash.update(part, "utf8");
  }
  return {
    commitmentDigest: "0x" + hash.digest("hex"),
    signed: false,
    onchainAttested: false,
  };
}
