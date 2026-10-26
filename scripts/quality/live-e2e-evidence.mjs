import { createHash } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
import { resolve, relative, sep } from "node:path";

const SHA256 = /^[a-f0-9]{64}$/;
const SHA256_0X = /^0x[a-f0-9]{64}$/;
const COMMIT = /^[a-f0-9]{40}$/;
const POSITIVE_DECIMAL = /^(0|[1-9][0-9]*)$/;
const SCENARIOS = [
  "funding_finalized",
  "developer_assigned",
  "baseline_failed",
  "patch_commit_verified",
  "candidate_and_regression_passed",
  "two_independent_attestations",
  "challenge_window_elapsed",
  "withdrawal_finalized",
  "refund_finalized",
  "unfunded_rejected",
  "wrong_network_rejected",
  "wrong_assignee_rejected",
  "tampered_manifest_rejected",
  "runner_escape_rejected",
  "timeout_rejected",
  "failed_wallet_tx_rejected",
  "rejected_verifier_rejected",
  "dispute_blocks_settlement",
  "rpc_outage_blocks_settlement",
  "webhook_replay_idempotent",
];

/**
 * This intake validates only the completeness and local bytes of externally
 * supplied evidence. It deliberately NEVER authorizes launch or asserts that
 * a fabricated live receipt is genuine. Chain explorers, GitHub API, testnet
 * state, participant identities and wallet custody MUST be independently
 * verified against trusted servers before any human release approval.
 */
export class E2EIntakeError extends Error {
  constructor(message) {
    super("E2E_EVIDENCE_INVALID: " + message);
    this.name = "E2EIntakeError";
  }
}
function check(ok, explanation) {
  if (!ok) throw new E2EIntakeError(explanation);
}
function record(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function exactKeys(value, names) {
  check(record(value), "expected structured object");
  check(
    Object.keys(value).sort().join("|") === [...names].sort().join("|"),
    "unexpected or missing evidence field",
  );
}
function httpsUrl(value) {
  try {
    const u = new URL(value);
    return (
      u.protocol === "https:" &&
      !u.username && !u.password && !u.hash &&
      !/(^|\.)(example|localhost|invalid|test|local)(\.|$)/i.test(u.hostname) &&
      !u.hostname.endsWith(".example.com") &&
      !u.hostname.startsWith("127.") &&
      !u.hostname.endsWith(".localhost") &&
      !u.hostname.includes("placeholder")
    );
  } catch {
    return false;
  }
}
function amount(value) {
  check(typeof value === "string" && POSITIVE_DECIMAL.test(value), "invalid exact atomic-unit amount");
  return BigInt(value);
}
function safeRelativePath(name) {
  check(
    typeof name === "string" &&
      name.length >= 5 && name.length <= 180 &&
      !name.startsWith("/") && !name.includes("\\") &&
      name.split("/").every((part) => part && part !== "." && part !== "..") &&
      /^[A-Za-z0-9._/-]+$/.test(name),
    "invalid evidence artifact relative path",
  );
}
async function digestLocalFile(root, item) {
  exactKeys(item, ["path", "sha256", "sizeBytes", "kind"]);
  safeRelativePath(item.path);
  check(SHA256.test(item.sha256), "invalid artifact sha256");
  check(Number.isSafeInteger(item.sizeBytes) && item.sizeBytes > 0 &&
    item.sizeBytes <= 50_000_000, "invalid artifact size");
  check(["receipt", "runner", "browser", "wallet", "github", "dispute", "report", "video"].includes(item.kind),
    "unknown artifact type");
  const absolute = resolve(root, item.path);
  const offset = relative(root, absolute);
  check(offset !== ".." && !offset.startsWith(".." + sep), "artifact path escaped evidence directory");
  const info = await stat(absolute);
  check(info.isFile() && !info.isSymbolicLink() && info.size === item.sizeBytes,
    "artifact missing, symlink or byte-length mismatch");
  const bytes = await readFile(absolute);
  check(createHash("sha256").update(bytes).digest("hex") === item.sha256,
    "evidence artifact byte hash mismatch");
}
function unique(values) {
  return new Set(values).size === values.length;
}

export async function validateLiveE2EIntakeV1(bundle, directory) {
  exactKeys(bundle, [
    "version", "claim", "sourceCommit", "network", "participants",
    "transactions", "escrowConservation", "scenarios", "artifacts",
    "independentReviewer",
  ]);
  check(bundle.version === "1" && bundle.claim === "live_evidence_submitted",
    "wrong evidence version or simulated/finalized status");
  check(typeof bundle.sourceCommit === "string" && COMMIT.test(bundle.sourceCommit),
    "unpinned source commit");

  exactKeys(bundle.network, ["networkName", "chainId", "genesisHash", "approvedRuntimeEvidenceUrl"]);
  check(
    typeof bundle.network.networkName === "string" &&
    /^[A-Za-z0-9_-]{3,64}$/.test(bundle.network.networkName) &&
    typeof bundle.network.chainId === "string" &&
    /^[1-9][0-9]{0,38}$/.test(bundle.network.chainId) &&
    SHA256_0X.test(bundle.network.genesisHash) &&
    httpsUrl(bundle.network.approvedRuntimeEvidenceUrl),
    "chain runtime identity not documented by approved HTTPS source",
  );
  exactKeys(bundle.participants, [
    "sponsorGitHubUserId", "contributorGitHubUserId",
    "verifierOrganizationIds", "independentReplayGitHubUserId",
  ]);
  const participants = bundle.participants;
  const ids = [participants.sponsorGitHubUserId, participants.contributorGitHubUserId,
    participants.independentReplayGitHubUserId];
  check(ids.every((id) => typeof id === "string" && /^[1-9][0-9]{0,18}$/.test(id)) &&
    unique(ids), "participants must be real distinct GitHub numeric identities");
  check(Array.isArray(participants.verifierOrganizationIds) &&
    participants.verifierOrganizationIds.length >= 2 &&
    participants.verifierOrganizationIds.length <= 12 &&
    unique(participants.verifierOrganizationIds) &&
    participants.verifierOrganizationIds.every((id) => typeof id === "string" &&
      /^[a-zA-Z0-9_-]{3,80}$/.test(id)), "two distinct verifier organizations required");

  check(Array.isArray(bundle.transactions) && bundle.transactions.length >= 3 &&
    bundle.transactions.length <= 50, "funding, payout and refund receipt references required");
  const necessaryTransactions = ["funding", "withdrawal", "refund"];
  for (const tx of bundle.transactions) {
    exactKeys(tx, ["purpose", "hash", "chainId", "explorerUrl", "confirmedBlockHash", "receiptArtifact"]);
    check(["funding", "withdrawal", "refund", "arbitration"].includes(tx.purpose),
      "unrecognized transaction purpose");
    check(SHA256_0X.test(tx.hash) && SHA256_0X.test(tx.confirmedBlockHash) &&
      tx.chainId === bundle.network.chainId && httpsUrl(tx.explorerUrl),
      "transaction identity, chain or explorer metadata invalid");
    safeRelativePath(tx.receiptArtifact);
  }
  check(necessaryTransactions.every((purpose) =>
    bundle.transactions.some((item) => item.purpose === purpose)),
    "missing required payout or refund receipt");
  check(unique(bundle.transactions.map((item) => item.hash)),
    "replayed transaction receipt");
  exactKeys(bundle.escrowConservation, [
    "openingAtoms", "depositsAtoms", "withdrawalsAtoms",
    "refundsAtoms", "closingAtoms",
  ]);
  const balance = bundle.escrowConservation;
  check(
    amount(balance.openingAtoms) + amount(balance.depositsAtoms) ===
    amount(balance.withdrawalsAtoms) + amount(balance.refundsAtoms) +
    amount(balance.closingAtoms),
    "escrow conservation claim inconsistent",
  );

  check(Array.isArray(bundle.scenarios) && bundle.scenarios.length === SCENARIOS.length,
    "complete positive and adversarial scenario inventory required");
  check(unique(bundle.scenarios.map((x) => x.name)), "duplicate scenario");
  const attachments = new Set();
  for (const s of bundle.scenarios) {
    exactKeys(s, ["name", "status", "evidenceArtifact"]);
    check(SCENARIOS.includes(s.name) && s.status === "observed_pass",
      "missing real live scenario evidence");
    safeRelativePath(s.evidenceArtifact);
    attachments.add(s.evidenceArtifact);
  }
  exactKeys(bundle.independentReviewer, ["githubUserId", "reviewUrl", "reviewArtifact"]);
  check(
    bundle.independentReviewer.githubUserId === participants.independentReplayGitHubUserId &&
      httpsUrl(bundle.independentReviewer.reviewUrl),
    "independent replay reviewer not bound",
  );
  safeRelativePath(bundle.independentReviewer.reviewArtifact);
  attachments.add(bundle.independentReviewer.reviewArtifact);
  for (const tx of bundle.transactions) attachments.add(tx.receiptArtifact);
  check(Array.isArray(bundle.artifacts) && bundle.artifacts.length >= 8 &&
    bundle.artifacts.length <= 80, "missing bounded artifact inventory");
  check(unique(bundle.artifacts.map((a) => a.path)), "duplicate artifact paths");
  const actual = new Set(bundle.artifacts.map((a) => a.path));
  for (const path of attachments) check(actual.has(path), "referenced evidence artifact not present");
  for (const artifact of bundle.artifacts) await digestLocalFile(directory, artifact);

  return {
    intake: "STRUCTURALLY_COMPLETE_UNVERIFIED",
    productionApproved: false,
    verifiedOnChain: false,
    reviewedIndependently: false,
    scenariosClaimed: bundle.scenarios.length,
    artifactsHashed: bundle.artifacts.length,
    note: "Only local byte integrity and stated metadata checked. Real chain/GitHub/reviewer provenance needs separate independent verification.",
  };
}

export const REQUIRED_LIVE_SCENARIOS_V1 = Object.freeze([...SCENARIOS]);
