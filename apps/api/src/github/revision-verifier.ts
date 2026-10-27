import { createHash } from "node:crypto";

/**
 * Exact, read-only GitHub App evidence validation. NOT registered as an API
 * endpoint and NOT usable for escrow settlement until #20/#23/#13.
 * All inputs other than the trusted GitHub API replies and installation
 * authorization must come from the immutable funded manifest + wallet session.
 */

const SHA = /^[a-f0-9]{40}$/;
const DIGEST = /^0x[a-f0-9]{64}$/;
const REPO_PART = /^[a-zA-Z0-9_.-]{1,100}$/;
const BASE_BRANCH = /^[a-zA-Z0-9][a-zA-Z0-9._/-]{0,99}$/;
const API_BASE = "https://api.github.com";

export type VerificationFailureCode =
  | "INVALID_SCHEMA"
  | "UNAUTHORIZED"
  | "FORBIDDEN"
  | "STALE_COMMIT"
  | "MANIFEST_MISMATCH"
  | "DEPENDENCY_UNAVAILABLE";

export class GitHubRevisionError extends Error {
  constructor(
    public readonly code: VerificationFailureCode,
    message: string,
  ) {
    super(message);
    this.name = "GitHubRevisionError";
  }
}

export interface PinnedRevisionPolicyV1 {
  repositoryId: number;
  repositoryFullName: string;
  pullNumber: number;
  baseCommitSha: string;
  headCommitSha: string;
  developerGitHubUserId: number;
  manifestDigest: string;
  imageDigest: string;
  allowForkPullRequests: boolean;
  requireVerifiedCommitSignature: boolean;
  baseBranch: string;
}

/** Values must come from an authenticated GitHub App installation context. */
export interface InstalledRepositoryPermissionsV1 {
  installationId: number;
  accessibleRepositoryIds: number[];
  granted: {
    contents: "none" | "read" | "write";
    pull_requests: "none" | "read" | "write";
  };
}

export interface GitHubRepositoryV1 {
  id: number;
  full_name: string;
  archived: boolean;
  disabled: boolean;
}

export interface GitHubPullV1 {
  number: number;
  state: string;
  base: { sha: string; ref: string; repo: { id: number } };
  head: { sha: string; repo: { id: number } | null };
  user: { id: number } | null;
}

export interface GitHubCommitV1 {
  sha: string;
  commit: { verification: { verified: boolean; reason: string | null } };
}

export interface GitHubSnapshotV1 {
  repo: GitHubRepositoryV1;
  pull: GitHubPullV1;
  commit: GitHubCommitV1;
}

export interface GitHubRevisionReceiptV1 {
  kind: "github-revision-snapshot-v1";
  repositoryId: number;
  repositoryFullName: string;
  pullNumber: number;
  sourceRepositoryId: number;
  fork: boolean;
  baseCommitSha: string;
  baseBranch: string;
  headCommitSha: string;
  developerGitHubUserId: number;
  installationId: number;
  commitSignatureVerified: boolean;
  manifestDigest: string;
  imageDigest: string;
  snapshotDigest: string;
}

/** Source and parent IDs are integer API fields; never coerce untrusted strings. */
function positiveSafeInt(value: number): boolean {
  return Number.isSafeInteger(value) && value > 0;
}

function validatePolicy(input: PinnedRevisionPolicyV1): void {
  if (
    !positiveSafeInt(input.repositoryId) ||
    !positiveSafeInt(input.pullNumber) ||
    !positiveSafeInt(input.developerGitHubUserId)
  ) {
    throw new GitHubRevisionError(
      "INVALID_SCHEMA",
      "Invalid numeric repository, PR or developer identity",
    );
  }
  const parts = input.repositoryFullName.split("/");
  if (
    parts.length !== 2 ||
    parts.some((part) => !REPO_PART.test(part) || part === "." || part === "..")
  ) {
    throw new GitHubRevisionError(
      "INVALID_SCHEMA",
      "Repository coordinate is not owner/name",
    );
  }
  if (
    !SHA.test(input.baseCommitSha) ||
    !SHA.test(input.headCommitSha) ||
    input.baseCommitSha === input.headCommitSha ||
    !DIGEST.test(input.manifestDigest) ||
    !DIGEST.test(input.imageDigest)
  ) {
    throw new GitHubRevisionError(
      "INVALID_SCHEMA",
      "Noncanonical or missing immutable proof fields",
    );
  }
  if (
    typeof input.allowForkPullRequests !== "boolean" ||
    typeof input.requireVerifiedCommitSignature !== "boolean" ||
    typeof input.baseBranch !== "string" ||
    !BASE_BRANCH.test(input.baseBranch) ||
    input.baseBranch
      .split("/")
      .some((segment) => segment === "." || segment === "..")
  ) {
    throw new GitHubRevisionError(
      "INVALID_SCHEMA",
      "Explicit fork, commit-signing and sponsor-approved base branch policy required",
    );
  }
}

function validatePermissions(
  policy: PinnedRevisionPolicyV1,
  access: InstalledRepositoryPermissionsV1,
): void {
  if (!positiveSafeInt(access.installationId)) {
    throw new GitHubRevisionError(
      "UNAUTHORIZED",
      "Missing authenticated GitHub App installation",
    );
  }
  if (
    !Array.isArray(access.accessibleRepositoryIds) ||
    !access.accessibleRepositoryIds.includes(policy.repositoryId)
  ) {
    throw new GitHubRevisionError(
      "FORBIDDEN",
      "GitHub App installation does not have target repository access",
    );
  }
  if (
    !["read", "write"].includes(access.granted.contents) ||
    !["read", "write"].includes(access.granted.pull_requests)
  ) {
    throw new GitHubRevisionError(
      "FORBIDDEN",
      "GitHub App needs Contents + Pull requests read permissions",
    );
  }
}

/**
 * Validates immutable GitHub API facts and generates an UNSIGNED evidence hash.
 * Only a signer authorized under #13 may later make a cryptographic attestation.
 */
export function verifyGitHubRevisionSnapshotV1(
  policy: PinnedRevisionPolicyV1,
  access: InstalledRepositoryPermissionsV1,
  snapshot: GitHubSnapshotV1,
): GitHubRevisionReceiptV1 {
  validatePolicy(policy);
  validatePermissions(policy, access);

  if (!snapshot.repo || snapshot.repo.id !== policy.repositoryId) {
    throw new GitHubRevisionError(
      "STALE_COMMIT",
      "Repository numeric identity changed or cannot be proven",
    );
  }
  if (
    snapshot.repo.full_name.toLowerCase() !==
    policy.repositoryFullName.toLowerCase()
  ) {
    // Rename/transfer is NOT permission to silently alter funded manifest.
    throw new GitHubRevisionError(
      "MANIFEST_MISMATCH",
      "Repository renamed/transferred: sponsor must approve a new funded manifest",
    );
  }
  if (snapshot.repo.archived || snapshot.repo.disabled) {
    throw new GitHubRevisionError(
      "FORBIDDEN",
      "Repository no longer accepts submissions",
    );
  }
  const p = snapshot.pull;
  if (
    !p ||
    p.number !== policy.pullNumber ||
    p.base?.repo?.id !== policy.repositoryId ||
    p.state !== "open"
  ) {
    throw new GitHubRevisionError(
      "STALE_COMMIT",
      "PR is missing, closed or belongs to a different repository",
    );
  }
  if (
    p.base.sha !== policy.baseCommitSha ||
    p.base.ref !== policy.baseBranch ||
    p.head.sha !== policy.headCommitSha
  ) {
    throw new GitHubRevisionError(
      "STALE_COMMIT",
      "PR moved from the sponsor-approved baseline/head revision",
    );
  }
  if (!p.user || p.user.id !== policy.developerGitHubUserId) {
    throw new GitHubRevisionError(
      "UNAUTHORIZED",
      "PR author is not the developer bound to the accepted wallet",
    );
  }
  if (!p.head.repo || !positiveSafeInt(p.head.repo.id)) {
    throw new GitHubRevisionError(
      "STALE_COMMIT",
      "Fork/repository source was deleted or cannot be authenticated",
    );
  }

  const fork = p.head.repo.id !== policy.repositoryId;
  if (fork && !policy.allowForkPullRequests) {
    throw new GitHubRevisionError(
      "FORBIDDEN",
      "Fork PR is forbidden under the funded sponsor policy",
    );
  }
  if (
    !snapshot.commit ||
    snapshot.commit.sha !== policy.headCommitSha ||
    typeof snapshot.commit.commit?.verification?.verified !== "boolean"
  ) {
    throw new GitHubRevisionError(
      "STALE_COMMIT",
      "Commit record is missing or does not match pinned SHA",
    );
  }
  const commitSignatureVerified = snapshot.commit.commit.verification.verified;
  if (policy.requireVerifiedCommitSignature && !commitSignatureVerified) {
    throw new GitHubRevisionError(
      "FORBIDDEN",
      "The GitHub commit signature is not verified",
    );
  }

  const fields = {
    kind: "github-revision-snapshot-v1" as const,
    repositoryId: policy.repositoryId,
    repositoryFullName: snapshot.repo.full_name,
    pullNumber: p.number,
    sourceRepositoryId: p.head.repo.id,
    fork,
    baseCommitSha: p.base.sha,
    baseBranch: p.base.ref,
    headCommitSha: p.head.sha,
    developerGitHubUserId: p.user.id,
    installationId: access.installationId,
    commitSignatureVerified,
    manifestDigest: policy.manifestDigest,
    imageDigest: policy.imageDigest,
  };
  // This only pins a successfully validated API snapshot at one instant.
  // A hash alone does NOT prove that an authenticated GitHub request happened.
  const snapshotDigest =
    "0x" + createHash("sha256").update(JSON.stringify(fields)).digest("hex");

  return {
    kind: fields.kind,
    repositoryId: fields.repositoryId,
    repositoryFullName: fields.repositoryFullName,
    pullNumber: fields.pullNumber,
    sourceRepositoryId: fields.sourceRepositoryId,
    fork: fields.fork,
    baseCommitSha: fields.baseCommitSha,
    baseBranch: fields.baseBranch,
    headCommitSha: fields.headCommitSha,
    developerGitHubUserId: fields.developerGitHubUserId,
    installationId: fields.installationId,
    commitSignatureVerified: fields.commitSignatureVerified,
    manifestDigest: fields.manifestDigest,
    imageDigest: fields.imageDigest,
    snapshotDigest,
  };
}

/**
 * Minimal read-only GitHub REST proof fetch. The caller is a PROTECTED backend
 * GitHub App integration (#20), never browser/PR code. No arbitrary URLs.
 */
export async function fetchGitHubRevisionSnapshotV1(
  policy: PinnedRevisionPolicyV1,
  installationToken: string,
  request: typeof fetch = fetch,
): Promise<GitHubSnapshotV1> {
  validatePolicy(policy);
  if (typeof installationToken !== "string" || installationToken.length < 8) {
    throw new GitHubRevisionError(
      "UNAUTHORIZED",
      "GitHub App installation token required",
    );
  }
  const [owner, repository] = policy.repositoryFullName.split("/");
  const prefix =
    "/repos/" +
    encodeURIComponent(owner) +
    "/" +
    encodeURIComponent(repository);

  async function read(path: string): Promise<any> {
    const response = await request(API_BASE + path, {
      method: "GET",
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: "Bearer " + installationToken,
        "X-GitHub-Api-Version": "2022-11-28",
      },
      redirect: "error",
      cache: "no-store",
    });
    if (response.status === 401)
      throw new GitHubRevisionError(
        "UNAUTHORIZED",
        "GitHub token expired or invalid",
      );
    if (response.status === 403 || response.status === 404) {
      throw new GitHubRevisionError(
        "FORBIDDEN",
        "GitHub App token lacks repository read access",
      );
    }
    if (!response.ok)
      throw new GitHubRevisionError(
        "DEPENDENCY_UNAVAILABLE",
        "GitHub API unavailable",
      );
    return response.json();
  }

  const repo: GitHubRepositoryV1 = await read(prefix);
  if (repo.id !== policy.repositoryId) {
    throw new GitHubRevisionError(
      "STALE_COMMIT",
      "Repository numeric ID mismatch",
    );
  }
  const pull: GitHubPullV1 = await read(prefix + "/pulls/" + policy.pullNumber);
  const commit: GitHubCommitV1 = await read(
    prefix + "/commits/" + encodeURIComponent(policy.headCommitSha),
  );
  return { repo, pull, commit };
}
