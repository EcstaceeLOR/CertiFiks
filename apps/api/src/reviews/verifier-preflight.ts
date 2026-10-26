/**
 * Server-side-only verifier review preflight. Never import in client bundles.
 * The caller MUST derive the actor from a separately verified session.
 *
 * This API reports untrusted runner outcomes for review. It does not sign,
 * attest, unlock private evidence, adjudicate or authorize chain payouts.
 */
const UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const SHA256 = /^0x[a-f0-9]{64}$/;
const COMMIT = /^[a-f0-9]{40}$/;
const OUTCOMES = new Set([
  "passed_claim",
  "failed_claim",
  "needs_review",
  "inconclusive",
]);

export interface VerifierReviewPreflightV1 {
  organizationId: string;
  bountyId: string;
  attemptId: string;
  runId: string;
  baseCommitSha: string;
  headCommitSha: string;
  manifestDigest: string;
  planDigest: string;
  runnerImageDigest: string;
  resultDigest: string | null;
  reportedOutcome: string;
  completedAt: string | null;
  artifactCount: number;
  canAttest: false;
  payoutAuthorized: false;
}

function blocked(message: string): never {
  throw new Error(`VERIFIER_PREFLIGHT_BLOCKED: ${message}`);
}

function asRecord(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return blocked("untrusted server result");
  }
  return value as Record<string, unknown>;
}

function parseRow(input: unknown): VerifierReviewPreflightV1 {
  const row = asRecord(input);
  for (const key of ["organization_id", "bounty_id", "attempt_id", "run_id"]) {
    if (typeof row[key] !== "string" || !UUID.test(row[key])) {
      blocked("invalid review identity");
    }
  }
  for (const key of ["base_commit_sha", "head_commit_sha"]) {
    if (typeof row[key] !== "string" || !COMMIT.test(row[key])) {
      blocked("unpinned commit");
    }
  }
  for (const key of [
    "funded_manifest_digest",
    "plan_digest",
    "runner_image_digest",
  ]) {
    if (typeof row[key] !== "string" || !SHA256.test(row[key])) {
      blocked("uncommitted reviewer evidence");
    }
  }
  if (
    row.result_digest !== null &&
    (typeof row.result_digest !== "string" || !SHA256.test(row.result_digest))
  )
    blocked("invalid reported result digest");
  if (
    typeof row.runner_outcome !== "string" ||
    !OUTCOMES.has(row.runner_outcome)
  ) {
    blocked("unexpected reported outcome");
  }
  if (
    row.completed_at !== null &&
    (typeof row.completed_at !== "string" ||
      !Number.isFinite(Date.parse(row.completed_at)))
  )
    blocked("invalid review timestamp");
  if (
    typeof row.artifact_count !== "number" ||
    !Number.isSafeInteger(row.artifact_count) ||
    row.artifact_count < 0 ||
    row.artifact_count > 100
  )
    blocked("untrusted artifact count");
  if (row.can_attest !== false || row.payout_authorized !== false) {
    blocked("unauthorized signer or payout flag");
  }
  return {
    organizationId: row.organization_id as string,
    bountyId: row.bounty_id as string,
    attemptId: row.attempt_id as string,
    runId: row.run_id as string,
    baseCommitSha: row.base_commit_sha as string,
    headCommitSha: row.head_commit_sha as string,
    manifestDigest: row.funded_manifest_digest as string,
    planDigest: row.plan_digest as string,
    runnerImageDigest: row.runner_image_digest as string,
    resultDigest: row.result_digest as string | null,
    reportedOutcome: row.runner_outcome as string,
    completedAt: row.completed_at as string | null,
    artifactCount: row.artifact_count as number,
    canAttest: false,
    payoutAuthorized: false,
  };
}

export class ServerVerifierReviewClientV1 {
  private readonly endpoint: string;
  constructor(
    supabaseUrl: string,
    private readonly serviceRoleKey: string,
    private readonly request: typeof fetch = fetch,
  ) {
    const url = new URL(supabaseUrl);
    if (
      url.protocol !== "https:" ||
      !url.hostname.endsWith(".supabase.co") ||
      url.username ||
      url.password ||
      url.search ||
      url.hash ||
      typeof serviceRoleKey !== "string" ||
      serviceRoleKey.length < 16
    )
      blocked("trusted server-only Supabase configuration is required");
    this.endpoint = new URL(
      "/rest/v1/rpc/certifiks_verifier_review_preflight",
      url,
    ).href;
  }

  /** Actor UUID must be obtained from independently authenticated server session. */
  async list(
    organizationId: string,
    trustedActorUserId: string,
    limit = 25,
  ): Promise<VerifierReviewPreflightV1[]> {
    if (
      !UUID.test(organizationId) ||
      !UUID.test(trustedActorUserId) ||
      !Number.isSafeInteger(limit) ||
      limit < 1 ||
      limit > 50
    )
      blocked("invalid review principal or pagination");
    let response: Response;
    try {
      response = await this.request(this.endpoint, {
        method: "POST",
        redirect: "error",
        cache: "no-store",
        headers: {
          apikey: this.serviceRoleKey,
          Authorization: `Bearer ${this.serviceRoleKey}`,
          "content-type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify({
          p_organization_id: organizationId,
          p_actor_user_id: trustedActorUserId,
          p_limit: limit,
        }),
        signal: AbortSignal.timeout(8000),
      });
    } catch {
      blocked("reviewer database unavailable");
    }
    if (!response.ok) blocked("reviewer authorization or database unavailable");
    let result: unknown;
    try {
      result = await response.json();
    } catch {
      blocked("invalid review server response");
    }
    if (!Array.isArray(result) || result.length > limit) {
      blocked("invalid review queue length");
    }
    const parsed = result.map(parseRow);
    if (parsed.some((row) => row.organizationId !== organizationId)) {
      blocked("cross-tenant review response");
    }
    return parsed;
  }
}
