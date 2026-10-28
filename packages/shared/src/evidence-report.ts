import {
  createHash,
  createPrivateKey,
  createPublicKey,
  sign,
  timingSafeEqual,
  verify,
} from "node:crypto";
import canonicalize from "canonicalize";

/**
 * Verifies evidence integrity, never correctness of test verdicts, signer
 * independence governance or entitlement to an escrow payout.
 *
 * Production enrollment certificates and trusted organizational identities
 * MUST come from an independently authenticated enrollment registry.
 */
const DOMAIN = "CertiFiks:evidence-report:v1\0";
const SHA256 = /^0x[a-f0-9]{64}$/;
const COMMIT = /^[a-f0-9]{40}$/;
const UINT = /^[1-9][0-9]*$/;
const ROLES = ["baseline-log", "candidate-log", "regression-log"] as const;
type ArtifactRole = (typeof ROLES)[number];

export interface EvidenceArtifactV1 {
  role: ArtifactRole;
  sha256: string;
  sizeBytes: number;
  visibility: "private";
}

export interface EvidenceReportV1 {
  version: "1";
  repositoryId: string;
  bountyId: string;
  attemptId: string;
  manifestDigest: string;
  imageDigest: string;
  baseCommitSha: string;
  headCommitSha: string;
  testPlanDigest: string;
  runnerResultDigest: string;
  createdAt: string;
  reportedDecision: "qualified" | "rejected" | "needs_review" | "inconclusive";
  artifacts: EvidenceArtifactV1[];
}

export interface EvidenceSignatureV1 {
  keyId: string;
  organizationId: string;
  algorithm: "Ed25519";
  signatureBase64: string;
}

export interface SignedEvidenceBundleV1 {
  report: EvidenceReportV1;
  reportDigest: string;
  signatures: EvidenceSignatureV1[];
}

export interface TrustedEvidenceSignerV1 {
  keyId: string;
  organizationId: string;
  publicKeyPem: string;
  revoked?: boolean;
}

export interface EvidencePrivateSignerV1 {
  keyId: string;
  organizationId: string;
  privateKeyPem: string;
}

export type EvidenceArtifactBytesV1 = Record<ArtifactRole, Uint8Array>;

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(`EVIDENCE_INVALID: ${message}`);
}

function sha256(value: Uint8Array | string): string {
  return "0x" + createHash("sha256").update(value).digest("hex");
}

function onlyKeys(value: unknown, allowed: string[]): void {
  assert(
    value !== null && typeof value === "object" && !Array.isArray(value),
    "expected object",
  );
  const found = Object.keys(value).sort();
  assert(
    found.length === allowed.length &&
      found.every((key, i) => key === [...allowed].sort()[i]),
    "missing or unexpected fields",
  );
}

function assertCanonicalId(value: unknown): void {
  assert(
    typeof value === "string" && UINT.test(value) && BigInt(value) < 2n ** 256n,
    "invalid numeric ID",
  );
}

function validateReport(report: EvidenceReportV1): void {
  onlyKeys(report, [
    "version",
    "repositoryId",
    "bountyId",
    "attemptId",
    "manifestDigest",
    "imageDigest",
    "baseCommitSha",
    "headCommitSha",
    "testPlanDigest",
    "runnerResultDigest",
    "createdAt",
    "reportedDecision",
    "artifacts",
  ]);
  assert(report.version === "1", "unsupported report version");
  for (const id of [report.repositoryId, report.bountyId, report.attemptId])
    assertCanonicalId(id);
  for (const value of [
    report.manifestDigest,
    report.imageDigest,
    report.testPlanDigest,
    report.runnerResultDigest,
  ])
    assert(typeof value === "string" && SHA256.test(value), "invalid digest");
  assert(
    COMMIT.test(report.baseCommitSha) &&
      COMMIT.test(report.headCommitSha) &&
      report.baseCommitSha !== report.headCommitSha,
    "invalid commit binding",
  );
  assert(
    typeof report.createdAt === "string" &&
      /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(report.createdAt) &&
      !Number.isNaN(Date.parse(report.createdAt)) &&
      new Date(report.createdAt).toISOString() === report.createdAt,
    "invalid timestamp",
  );
  assert(
    ["qualified", "rejected", "needs_review", "inconclusive"].includes(
      report.reportedDecision,
    ),
    "invalid stated decision",
  );
  assert(
    Array.isArray(report.artifacts) && report.artifacts.length === ROLES.length,
    "missing evidence artifacts",
  );
  for (let i = 0; i < ROLES.length; i++) {
    const artifact = report.artifacts[i];
    onlyKeys(artifact, ["role", "sha256", "sizeBytes", "visibility"]);
    assert(artifact.role === ROLES[i], "missing or reordered artifact");
    assert(SHA256.test(artifact.sha256), "invalid artifact digest");
    assert(
      Number.isSafeInteger(artifact.sizeBytes) &&
        artifact.sizeBytes > 0 &&
        artifact.sizeBytes <= 1024 * 1024,
      "invalid artifact byte count",
    );
    assert(
      artifact.visibility === "private",
      "execution logs cannot be publicly disclosed",
    );
  }
}

function reportDigest(report: EvidenceReportV1): string {
  validateReport(report);
  const json = canonicalize(report);
  assert(typeof json === "string", "non-canonical report");
  return sha256(Buffer.from(DOMAIN + json, "utf8"));
}

function signingBytes(digest: string): Buffer {
  return Buffer.from(DOMAIN + digest, "utf8");
}

/** Build the manifest without emitting logs to public report JSON. */
export function createEvidenceReportV1(
  fields: Omit<EvidenceReportV1, "version" | "artifacts">,
  files: EvidenceArtifactBytesV1,
): EvidenceReportV1 {
  const artifacts = ROLES.map((role) => {
    const bytes = files[role];
    assert(
      bytes instanceof Uint8Array &&
        bytes.byteLength > 0 &&
        bytes.byteLength <= 1024 * 1024,
      "missing or excessive private artifact",
    );
    return {
      role,
      sha256: sha256(bytes),
      sizeBytes: bytes.byteLength,
      visibility: "private" as const,
    };
  });
  const report: EvidenceReportV1 = { ...fields, version: "1", artifacts };
  validateReport(report);
  return report;
}

export function signEvidenceReportV1(
  report: EvidenceReportV1,
  signer: EvidencePrivateSignerV1,
): EvidenceSignatureV1 {
  assert(
    /^[a-zA-Z0-9_-]{3,80}$/.test(signer.keyId) &&
      /^[a-zA-Z0-9_-]{3,80}$/.test(signer.organizationId),
    "invalid signer identity",
  );
  const key = createPrivateKey(signer.privateKeyPem);
  assert(key.asymmetricKeyType === "ed25519", "Ed25519 identity key required");
  return {
    keyId: signer.keyId,
    organizationId: signer.organizationId,
    algorithm: "Ed25519",
    signatureBase64: sign(
      null,
      signingBytes(reportDigest(report)),
      key,
    ).toString("base64"),
  };
}

export function assembleEvidenceBundleV1(
  report: EvidenceReportV1,
  signatures: EvidenceSignatureV1[],
): SignedEvidenceBundleV1 {
  assert(Array.isArray(signatures), "invalid signatures");
  return { report, reportDigest: reportDigest(report), signatures };
}

/**
 * All required private artifacts must be supplied by a separately authorized
 * caller. An absent or byte-tampered artifact fails closed and cannot be
 * interpreted as verification success or authorization to release funds.
 *
 * The trusted signer roster must come from the approved, versioned registry;
 * untrusted report content cannot install its own public keys.
 */
export function verifyEvidenceBundleV1(
  bundle: SignedEvidenceBundleV1,
  roster: TrustedEvidenceSignerV1[],
  files: EvidenceArtifactBytesV1,
): {
  integrity: "verified";
  reportedDecision: EvidenceReportV1["reportedDecision"];
  payoutAuthorized: false;
} {
  onlyKeys(bundle, ["report", "reportDigest", "signatures"]);
  assert(SHA256.test(bundle.reportDigest), "invalid report digest");
  const digest = reportDigest(bundle.report);
  assert(
    timingSafeEqual(
      Buffer.from(bundle.reportDigest.slice(2), "hex"),
      Buffer.from(digest.slice(2), "hex"),
    ),
    "report tampering detected",
  );
  for (const item of bundle.report.artifacts) {
    const bytes = files?.[item.role];
    assert(bytes instanceof Uint8Array, "missing private artifact");
    assert(bytes.byteLength === item.sizeBytes, "artifact size mismatch");
    assert(
      timingSafeEqual(
        Buffer.from(item.sha256.slice(2), "hex"),
        Buffer.from(sha256(bytes).slice(2), "hex"),
      ),
      "private artifact tampering detected",
    );
  }
  assert(
    Array.isArray(roster) &&
      Array.isArray(bundle.signatures) &&
      bundle.signatures.length >= 2 &&
      bundle.signatures.length <= 16,
    "at least two enrolled independent reviewers required",
  );
  const orgs = new Set<string>();
  const keys = new Set<string>();
  const publicKeyFingerprints = new Set<string>();
  for (const entry of bundle.signatures) {
    onlyKeys(entry, [
      "keyId",
      "organizationId",
      "algorithm",
      "signatureBase64",
    ]);
    assert(entry.algorithm === "Ed25519", "wrong signature algorithm");
    assert(
      typeof entry.keyId === "string" &&
        typeof entry.organizationId === "string",
      "missing signer identity",
    );
    assert(
      !orgs.has(entry.organizationId) && !keys.has(entry.keyId),
      "duplicate reviewer organization or key",
    );
    orgs.add(entry.organizationId);
    keys.add(entry.keyId);
    const trusted = roster.find(
      (item) =>
        item.keyId === entry.keyId &&
        item.organizationId === entry.organizationId &&
        !item.revoked,
    );
    assert(trusted, "untrusted or revoked evidence signer");
    assert(
      typeof entry.signatureBase64 === "string" &&
        /^[A-Za-z0-9+/]{86}==$/.test(entry.signatureBase64),
      "invalid signature encoding",
    );
    const signature = Buffer.from(entry.signatureBase64, "base64");
    assert(signature.length === 64, "wrong signature length");
    const publicKey = createPublicKey(trusted.publicKeyPem);
    assert(publicKey.asymmetricKeyType === "ed25519", "invalid trust anchor");
    // Distinct organization labels are not enough: the same Ed25519 key
    // registered under two different IDs cannot form an independent quorum.
    const fingerprint = sha256(
      publicKey.export({ format: "der", type: "spki" }),
    );
    assert(
      !publicKeyFingerprints.has(fingerprint),
      "duplicate signer key material across reviewer organizations",
    );
    publicKeyFingerprints.add(fingerprint);
    assert(
      verify(null, signingBytes(digest), publicKey, signature),
      "evidence signature verification failed",
    );
  }
  return {
    integrity: "verified",
    reportedDecision: bundle.report.reportedDecision,
    payoutAuthorized: false,
  };
}
