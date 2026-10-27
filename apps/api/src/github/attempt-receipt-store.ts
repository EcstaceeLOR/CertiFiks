import type { GitHubAppCredentials } from "./app-auth.js";
import {
  getAuthenticatedRevisionReceiptV1,
  type VerifiedGitHubConnectionV1,
} from "./authenticated-revision.js";
import type {
  GitHubRevisionReceiptV1,
  PinnedRevisionPolicyV1,
} from "./revision-verifier.js";

const UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;

/**
 * Only a protected service is allowed to provide these values, after binding
 * the authenticated wallet, GitHub user and tenant to an immutable DB attempt.
 * NEVER expose this helper directly to browser/partner-supplied policy.
 */
export interface TrustedAttemptContextV1 {
  organizationId: string;
  bountyId: string;
  attemptId: string;
  authenticatedOwnerUserId: string;
}

export interface AttemptReceiptPersistenceV1 {
  supabaseUrl: string;
  serviceRoleKey: string;
  request?: typeof fetch;
}

export class GitHubReceiptPersistenceError extends Error {
  constructor(
    public readonly code:
      | "MISCONFIGURED"
      | "ALREADY_PINNED"
      | "PERSISTENCE_UNAVAILABLE",
  ) {
    super(code);
    this.name = "GitHubReceiptPersistenceError";
  }
}

function receiptEndpoint(options: AttemptReceiptPersistenceV1): URL {
  try {
    const base = new URL(options.supabaseUrl);
    if (
      base.protocol !== "https:" ||
      !base.hostname.endsWith(".supabase.co") ||
      base.hostname === ".supabase.co" ||
      base.username ||
      base.password ||
      base.port ||
      base.search ||
      base.hash ||
      options.serviceRoleKey.length < 16
    ) {
      throw new Error("Invalid internal data endpoint");
    }
    return new URL("/rest/v1/certifiks_github_revision_receipts", base);
  } catch {
    throw new GitHubReceiptPersistenceError("MISCONFIGURED");
  }
}

/**
 * Re-fetch the authentic PR through the consented GitHub App, then INSERT its
 * complete pinned snapshot through the server-only database API.
 *
 * No upsert: a force-push/retry may NEVER replace an earlier attempt. The
 * database additionally locks/checks tenant, repository, installation,
 * source/base/head SHAs and funded manifest. This is unsigned read evidence,
 * NOT independent validation of a fixed defect or approval for payout.
 */
export async function captureAuthenticatedGitHubAttemptV1(
  credentials: GitHubAppCredentials,
  connection: VerifiedGitHubConnectionV1,
  policy: PinnedRevisionPolicyV1,
  context: TrustedAttemptContextV1,
  persistence: AttemptReceiptPersistenceV1,
  githubRequest?: typeof fetch,
): Promise<GitHubRevisionReceiptV1> {
  if (
    !UUID.test(context.organizationId) ||
    !UUID.test(context.bountyId) ||
    !UUID.test(context.attemptId) ||
    !context.authenticatedOwnerUserId
  ) {
    throw new GitHubReceiptPersistenceError("MISCONFIGURED");
  }
  const endpoint = receiptEndpoint(persistence);
  const receipt = await getAuthenticatedRevisionReceiptV1(
    credentials,
    connection,
    policy,
    {
      requestedOwnerUserId: context.authenticatedOwnerUserId,
      request: githubRequest,
    },
  );
  let response: Response;
  try {
    response = await (persistence.request ?? fetch)(endpoint.href, {
      method: "POST",
      redirect: "error",
      cache: "no-store",
      signal: AbortSignal.timeout(8000),
      headers: {
        Accept: "application/json",
        "content-type": "application/json",
        Prefer: "return=minimal",
        apikey: persistence.serviceRoleKey,
        Authorization: `Bearer ${persistence.serviceRoleKey}`,
      },
      body: JSON.stringify({
        organization_id: context.organizationId,
        bounty_id: context.bountyId,
        attempt_id: context.attemptId,
        repository_id: receipt.repositoryId,
        source_repository_id: receipt.sourceRepositoryId,
        repository_full_name: receipt.repositoryFullName,
        installation_id: receipt.installationId,
        pull_number: receipt.pullNumber,
        developer_github_user_id: receipt.developerGitHubUserId,
        base_commit_sha: receipt.baseCommitSha,
        head_commit_sha: receipt.headCommitSha,
        manifest_digest: receipt.manifestDigest,
        image_digest: receipt.imageDigest,
        snapshot_digest: receipt.snapshotDigest,
        fork: receipt.fork,
        commit_signature_verified: receipt.commitSignatureVerified,
      }),
    });
  } catch {
    throw new GitHubReceiptPersistenceError("PERSISTENCE_UNAVAILABLE");
  }
  if (response.status === 409) {
    throw new GitHubReceiptPersistenceError("ALREADY_PINNED");
  }
  if (response.status !== 201 && response.status !== 204) {
    throw new GitHubReceiptPersistenceError("PERSISTENCE_UNAVAILABLE");
  }
  return receipt;
}
