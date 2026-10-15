import {
  GitHubAppAuthError,
  type GitHubAppCredentials,
  mintRepositoryInstallationToken,
} from "./app-auth.js";
import {
  fetchGitHubRevisionSnapshotV1,
  type GitHubRevisionReceiptV1,
  type PinnedRevisionPolicyV1,
  verifyGitHubRevisionSnapshotV1,
} from "./revision-verifier.js";

/**
 * A trusted installation binding must come from a user-authenticated,
 * consented, stored repo connection; never the caller's webhook payload.
 */
export interface VerifiedGitHubConnectionV1 {
  installationId: number;
  repositoryId: number;
  connectedOwnerUserId: string;
  active: boolean;
  consentRecorded: boolean;
}

/**
 * Protected worker-only authorization path: issue exactly scoped GitHub App
 * token and re-fetch the actual PR/commit under that installation before
 * publishing any UNSIGNED revision snapshot. No payout approvals.
 */
export async function getAuthenticatedRevisionReceiptV1(
  credentials: GitHubAppCredentials,
  trustedConnection: VerifiedGitHubConnectionV1,
  policy: PinnedRevisionPolicyV1,
  options: { requestedOwnerUserId: string; request?: typeof fetch },
): Promise<GitHubRevisionReceiptV1> {
  if (
    !trustedConnection.active ||
    !trustedConnection.consentRecorded ||
    !trustedConnection.connectedOwnerUserId ||
    trustedConnection.connectedOwnerUserId !== options.requestedOwnerUserId ||
    trustedConnection.repositoryId !== policy.repositoryId
  ) {
    throw new GitHubAppAuthError(
      "FORBIDDEN",
      "Repository owner consent or access revoked",
    );
  }
  const request = options.request ?? fetch;
  const scoped = await mintRepositoryInstallationToken(
    credentials,
    trustedConnection.installationId,
    trustedConnection.repositoryId,
    request,
  );
  const snapshot = await fetchGitHubRevisionSnapshotV1(
    policy,
    scoped.token,
    request,
  );
  return verifyGitHubRevisionSnapshotV1(policy, scoped.permissions, snapshot);
}
