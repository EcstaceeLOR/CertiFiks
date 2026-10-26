/**
 * Trusted backend transport for private, immutable dispute metadata.
 * Never call this from a browser and never derive actorId from request input.
 * A verified wallet/GitHub session MUST bind each invocation to the actor.
 */
const UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const HASH = /^0x[a-f0-9]{64}$/;
const HEX = /^[0-9a-f]{64}$/;
const KINDS = new Set([
  "case_opened",
  "party_response",
  "supporting_evidence",
  "arbitrator_note",
]);

export interface DisputeTimelineEntryV1 {
  timelineId: string;
  organizationId: string;
  disputeId: string;
  actorUserId: string;
  kind: string;
  reasonDigest: string;
  artifactDigest: string | null;
  eventIdempotency: string;
  createdAt: string;
  settlementAuthorized: false;
}

function fail(): never {
  throw new Error("DISPUTE_TIMELINE_UNAVAILABLE");
}

function parseEntry(value: unknown): DisputeTimelineEntryV1 {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail();
  const record = value as Record<string, unknown>;
  if (
    ["timeline_id", "organization_id", "dispute_id", "actor_user_id"].some(
      (key) =>
        typeof record[key] !== "string" || !UUID.test(record[key] as string),
    )
  )
    fail();
  if (
    typeof record.kind !== "string" ||
    !KINDS.has(record.kind) ||
    typeof record.reason_digest !== "string" ||
    !HASH.test(record.reason_digest) ||
    (record.artifact_digest !== null &&
      (typeof record.artifact_digest !== "string" ||
        !HASH.test(record.artifact_digest))) ||
    typeof record.event_idempotency !== "string" ||
    !HEX.test(record.event_idempotency) ||
    typeof record.created_at !== "string" ||
    !Number.isFinite(Date.parse(record.created_at))
  )
    fail();
  return {
    timelineId: record.timeline_id as string,
    organizationId: record.organization_id as string,
    disputeId: record.dispute_id as string,
    actorUserId: record.actor_user_id as string,
    kind: record.kind as string,
    reasonDigest: record.reason_digest as string,
    artifactDigest: record.artifact_digest as string | null,
    eventIdempotency: record.event_idempotency as string,
    createdAt: record.created_at as string,
    settlementAuthorized: false,
  };
}

export class PrivateDisputeTimelineClientV1 {
  private readonly endpoint: string;
  constructor(
    supabaseUrl: string,
    private readonly serverKey: string,
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
      typeof serverKey !== "string" ||
      serverKey.length < 16
    )
      fail();
    this.endpoint = new URL(
      "/rest/v1/rpc/certifiks_read_dispute_timeline",
      url,
    ).href;
  }

  async list(
    organizationId: string,
    disputeId: string,
    verifiedActorUserId: string,
    limit = 25,
  ): Promise<DisputeTimelineEntryV1[]> {
    if (
      ![organizationId, disputeId, verifiedActorUserId].every((id) =>
        UUID.test(id),
      ) ||
      !Number.isSafeInteger(limit) ||
      limit < 1 ||
      limit > 50
    )
      fail();
    let response: Response;
    try {
      response = await this.request(this.endpoint, {
        method: "POST",
        redirect: "error",
        cache: "no-store",
        headers: {
          "content-type": "application/json",
          Accept: "application/json",
          Authorization: `Bearer ${this.serverKey}`,
          apikey: this.serverKey,
        },
        body: JSON.stringify({
          p_org: organizationId,
          p_dispute: disputeId,
          p_actor: verifiedActorUserId,
          p_limit: limit,
        }),
        signal: AbortSignal.timeout(8000),
      });
    } catch {
      fail();
    }
    if (!response.ok) fail();
    let data: unknown;
    try {
      data = await response.json();
    } catch {
      fail();
    }
    if (!Array.isArray(data) || data.length > limit) fail();
    const entries = data.map(parseEntry);
    if (
      entries.some(
        (entry) =>
          entry.organizationId !== organizationId ||
          entry.disputeId !== disputeId,
      )
    )
      fail();
    return entries;
  }
}
