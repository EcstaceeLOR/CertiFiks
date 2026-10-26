/**
 * Privileged queue transport. Must live outside untrusted Docker execution
 * and be provisioned only in a separately secured verifier worker process.
 * The queue NEVER certifies a fix or triggers blockchain payments.
 */
const UUID = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/;
const DIGEST = /^0x[a-f0-9]{64}$/;
const ERROR = /^[A-Z0-9_]{3,64}$/;
const STAGES = new Set([
  "checkout", "baseline", "candidate", "regression",
  "review", "synchronize", "notify",
]);

export class VerificationQueueError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VerificationQueueError";
  }
}

export interface VerificationJobLeaseV1 {
  job_id: string;
  organization_id: string;
  bounty_id: string;
  attempt_id: string;
  manifest_digest: string;
  stage: string;
  status: "running";
  attempts: number;
  lease_id: string;
  lease_until: string;
}

function assert(value: unknown, error: string): asserts value {
  if (!value) throw new VerificationQueueError(error);
}

function isLease(value: unknown): value is VerificationJobLeaseV1 {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const row = value as Record<string, unknown>;
  return (
    ["job_id", "organization_id", "bounty_id", "attempt_id", "lease_id"].every(
      (key) => typeof row[key] === "string" && UUID.test(row[key] as string),
    ) &&
    typeof row.manifest_digest === "string" &&
    DIGEST.test(row.manifest_digest) &&
    typeof row.stage === "string" && STAGES.has(row.stage) &&
    row.status === "running" &&
    typeof row.attempts === "number" &&
    Number.isSafeInteger(row.attempts) && row.attempts >= 1 &&
    row.attempts <= 8 &&
    typeof row.lease_until === "string" &&
    Number.isFinite(Date.parse(row.lease_until))
  );
}

export class ServerVerificationQueueV1 {
  private readonly url: URL;
  constructor(
    supabaseUrl: string,
    private readonly serverKey: string,
    private readonly request: typeof fetch = fetch,
  ) {
    const parsed = new URL(supabaseUrl);
    assert(
      parsed.protocol === "https:" &&
      parsed.hostname.endsWith(".supabase.co") &&
      !parsed.username && !parsed.password && !parsed.search && !parsed.hash &&
      typeof serverKey === "string" && serverKey.length >= 16,
      "Production server-only Supabase credentials required",
    );
    this.url = new URL("/rest/v1/rpc/", parsed);
  }

  private async rpc(name: string, payload: object): Promise<unknown> {
    const endpoint = new URL(name, this.url);
    let response: Response;
    try {
      response = await this.request(endpoint.href, {
        method: "POST",
        headers: {
          apikey: this.serverKey,
          Authorization: `Bearer ${this.serverKey}`,
          Accept: "application/json",
          "content-type": "application/json",
        },
        body: JSON.stringify(payload),
        redirect: "error",
        cache: "no-store",
        signal: AbortSignal.timeout(8_000),
      });
    } catch {
      throw new VerificationQueueError("Queue database is unavailable");
    }
    if (!response.ok) throw new VerificationQueueError("Queue database rejected operation");
    try {
      return await response.json();
    } catch {
      throw new VerificationQueueError("Queue database returned invalid JSON");
    }
  }

  async enqueue(
    organizationId: string, bountyId: string, attemptId: string,
    manifestDigest: string, stage: string,
  ): Promise<string> {
    assert(
      [organizationId, bountyId, attemptId].every((id) => UUID.test(id)) &&
      DIGEST.test(manifestDigest) && STAGES.has(stage),
      "Untrusted or malformed job identity",
    );
    const value = await this.rpc("certifiks_enqueue_verification_stage", {
      p_org: organizationId,
      p_bounty: bountyId,
      p_attempt: attemptId,
      p_manifest: manifestDigest,
      p_stage: stage,
    });
    assert(typeof value === "string" && UUID.test(value), "Invalid enqueue receipt");
    return value;
  }

  async claim(limit = 5): Promise<VerificationJobLeaseV1[]> {
    assert(Number.isSafeInteger(limit) && limit > 0 && limit <= 25, "Invalid claim batch size");
    const value = await this.rpc("certifiks_claim_verification_jobs", { p_limit: limit });
    assert(Array.isArray(value) && value.length <= limit, "Invalid claim result");
    assert(value.every(isLease), "Invalid or unleased queue job");
    return value as VerificationJobLeaseV1[];
  }

  async heartbeat(job: VerificationJobLeaseV1): Promise<boolean> {
    assert(isLease(job), "Job lease is invalid");
    const value = await this.rpc("certifiks_heartbeat_verification_job", {
      p_job_id: job.job_id, p_lease: job.lease_id, p_attempt: job.attempts,
    });
    assert(typeof value === "boolean", "Unconfirmed lease heartbeat");
    return value;
  }

  async complete(
    job: VerificationJobLeaseV1,
    success: boolean,
    errorCode: string | null = null,
  ): Promise<boolean> {
    assert(isLease(job) && typeof success === "boolean", "Job lease is invalid");
    assert(success ? errorCode === null : errorCode === null || ERROR.test(errorCode),
      "Invalid error code");
    const value = await this.rpc("certifiks_complete_verification_job", {
      p_job_id: job.job_id,
      p_lease: job.lease_id,
      p_attempt: job.attempts,
      p_success: success,
      p_error_code: errorCode,
    });
    assert(typeof value === "boolean", "Unconfirmed job completion");
    return value;
  }

  async cancel(jobId: string, reason: string): Promise<boolean> {
    assert(UUID.test(jobId) && ERROR.test(reason), "Invalid cancellation request");
    const value = await this.rpc("certifiks_cancel_verification_job", {
      p_job_id: jobId,
      p_error_code: reason,
    });
    assert(typeof value === "boolean", "Unconfirmed job cancellation");
    return value;
  }
}
