import { createHash, createPublicKey, verify } from "node:crypto";

const COMMIT = /^[a-f0-9]{40}$/;
const DIGEST = /^[a-f0-9]{64}$/;
const TOKEN = /^[A-Za-z0-9_-]{3,96}$/;
const SCOPES = [
  "smart_contracts",
  "github_auth_and_webhooks",
  "api_tenant_boundaries",
  "verifier_sandbox",
  "wallet_and_settlement",
  "artifact_access",
];

/**
 * A signed independent review must come from an explicitly trusted,
 * out-of-band key and approved reviewer identity. A report-controlled public
 * key or same-owner reviewer is NOT a legitimate external security audit.
 */
export class SecurityReleaseBlockedError extends Error {
  constructor(message) {
    super("SECURITY_RELEASE_BLOCKED: " + message);
    this.name = "SecurityReleaseBlockedError";
  }
}
function failUnless(ok, why) {
  if (!ok) throw new SecurityReleaseBlockedError(why);
}
function object(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function requireKeys(value, names) {
  failUnless(object(value), "expected a JSON object");
  failUnless(
    Object.keys(value).sort().join("|") === [...names].sort().join("|"),
    "unexpected or missing review fields",
  );
}
export function canonicalReviewJson(value) {
  function walk(item) {
    if (Array.isArray(item)) return item.map(walk);
    if (object(item)) {
      const copy = {};
      for (const key of Object.keys(item).sort()) copy[key] = walk(item[key]);
      return copy;
    }
    return item;
  }
  return JSON.stringify(walk(value));
}

/**
 * Cryptographically authenticate the bytes of an out-of-band review.
 *
 * Return value DOES NOT assert production readiness or demonstrate that the
 * signed assertions are factually true. A human release panel must independently
 * confirm the reviewer, retests, software provenance and real network receipts.
 */
export function verifyIndependentSecurityReviewV1(
  rawCanonicalReportBytes,
  signatureBase64,
  trustedReviewerPublicKeyPem,
  expectedReleaseCommit,
  expectedReviewerOrganizationId,
) {
  failUnless(
    Buffer.isBuffer(rawCanonicalReportBytes) &&
      rawCanonicalReportBytes.byteLength > 0 &&
      rawCanonicalReportBytes.byteLength <= 500_000,
    "missing or oversized security review",
  );
  failUnless(
    typeof expectedReleaseCommit === "string" &&
      COMMIT.test(expectedReleaseCommit) &&
      typeof expectedReviewerOrganizationId === "string" &&
      TOKEN.test(expectedReviewerOrganizationId),
    "invalid trusted release and reviewer policy",
  );
  let report;
  try {
    report = JSON.parse(rawCanonicalReportBytes.toString("utf8"));
  } catch {
    throw new SecurityReleaseBlockedError("invalid reviewer report JSON");
  }
  requireKeys(report, [
    "version",
    "releaseCommit",
    "reviewerOrganizationId",
    "reviewedAt",
    "scopes",
    "findings",
    "sourceArchiveSha256",
    "sbomSha256",
    "testRunSha256",
    "reviewMethodologyUrl",
    "independentRetestUrl",
  ]);
  failUnless(
    report.version === "1" &&
      report.releaseCommit === expectedReleaseCommit &&
      report.reviewerOrganizationId === expectedReviewerOrganizationId,
    "wrong review version, release or independent organization binding",
  );
  failUnless(
    Buffer.from(canonicalReviewJson(report)).equals(rawCanonicalReportBytes),
    "report must use unambiguous canonical sorted JSON encoding",
  );
  const reportedAt = Date.parse(report.reviewedAt);
  failUnless(
    typeof report.reviewedAt === "string" &&
      /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(report.reviewedAt) &&
      Number.isFinite(reportedAt) &&
      new Date(reportedAt).toISOString() === report.reviewedAt,
    "untrusted or malformed review timestamp",
  );
  failUnless(
    Array.isArray(report.scopes) &&
      report.scopes.length === SCOPES.length &&
      SCOPES.every((name) => report.scopes.includes(name)) &&
      new Set(report.scopes).size === SCOPES.length,
    "security review omits required attack surface",
  );
  for (const field of ["sourceArchiveSha256", "sbomSha256", "testRunSha256"]) {
    failUnless(
      typeof report[field] === "string" && DIGEST.test(report[field]),
      "missing pinned supply-chain or test provenance digest",
    );
  }
  for (const field of ["reviewMethodologyUrl", "independentRetestUrl"]) {
    let target;
    try {
      target = new URL(report[field]);
    } catch {
      throw new SecurityReleaseBlockedError(
        "unusable signed review evidence URL",
      );
    }
    failUnless(
      target.protocol === "https:" &&
        !target.username &&
        !target.password &&
        !/(^|\.)(example|localhost|invalid|test)(\.|$)/i.test(target.hostname),
      "review evidence must use non-placeholder HTTPS",
    );
  }
  failUnless(
    Array.isArray(report.findings) && report.findings.length <= 1000,
    "invalid security finding inventory",
  );
  const seen = new Set();
  for (const item of report.findings) {
    requireKeys(item, [
      "findingId",
      "severity",
      "status",
      "retestEvidenceSha256",
    ]);
    failUnless(
      typeof item.findingId === "string" &&
        TOKEN.test(item.findingId) &&
        !seen.has(item.findingId) &&
        ["critical", "high", "medium", "low", "informational"].includes(
          item.severity,
        ) &&
        ["remediated_retested", "unresolved", "risk_accepted"].includes(
          item.status,
        ),
      "malformed or duplicate independent finding",
    );
    seen.add(item.findingId);
    failUnless(
      item.retestEvidenceSha256 === null ||
        (typeof item.retestEvidenceSha256 === "string" &&
          DIGEST.test(item.retestEvidenceSha256)),
      "invalid retest evidence digest",
    );
    if (item.severity === "critical" || item.severity === "high") {
      failUnless(
        item.status === "remediated_retested" &&
          item.retestEvidenceSha256 !== null,
        "critical or high severity findings lack independent retest",
      );
    }
  }

  failUnless(
    typeof signatureBase64 === "string" &&
      /^[A-Za-z0-9+/]{86}==$/.test(signatureBase64),
    "missing canonical Ed25519 review signature",
  );
  let trustedKey;
  try {
    trustedKey = createPublicKey(trustedReviewerPublicKeyPem);
  } catch {
    throw new SecurityReleaseBlockedError(
      "trusted review key could not be loaded",
    );
  }
  failUnless(
    trustedKey.asymmetricKeyType === "ed25519",
    "independently approved Ed25519 reviewer key required",
  );
  const signature = Buffer.from(signatureBase64, "base64");
  failUnless(
    signature.length === 64 &&
      verify(null, rawCanonicalReportBytes, trustedKey, signature),
    "independent review signature mismatch",
  );

  return {
    releaseCommit: expectedReleaseCommit,
    reviewBytesSha256: createHash("sha256")
      .update(rawCanonicalReportBytes)
      .digest("hex"),
    verifiedReviewerSignature: true,
    unresolvedCriticalOrHigh: false,
    reviewScopes: SCOPES.length,
    findingsRecorded: report.findings.length,
    productionApproved: false,
    note: "Only cryptographic report authenticity and stated finding remediation were checked. Independent on-chain, GitHub, sandbox, artifact and auditor verification is mandatory.",
  };
}
