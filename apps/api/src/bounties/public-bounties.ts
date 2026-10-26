const ID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const DECIMAL = /^(0|[1-9][0-9]*)$/;
const SHA256 = /^0x[a-f0-9]{64}$/;
const STATES = new Set([
  "funded",
  "assigned",
  "submitted",
  "verifying",
  "review",
  "disputed",
  "payable",
  "settled",
  "refunded",
]);

export interface PublicBountyV1 {
  bountyId: string;
  repositoryId: string;
  repositoryFullName: string;
  chainId: string;
  onchainBountyId: string;
  rewardAtoms: string;
  manifestDigest: string;
  state: string;
  createdAt: string;
  verificationProven: false;
}

function assertField(condition: unknown): asserts condition {
  if (!condition) throw new Error("PUBLIC_BOUNTY_UPSTREAM_DATA_INVALID");
}

function parseRecord(row: unknown): PublicBountyV1 {
  assertField(row !== null && typeof row === "object" && !Array.isArray(row));
  const record = row as Record<string, unknown>;
  assertField(
    typeof record.bounty_id === "string" && ID.test(record.bounty_id),
  );
  for (const key of [
    "repository_id",
    "chain_id",
    "onchain_bounty_id",
    "reward_atoms",
  ]) {
    assertField(typeof record[key] === "string" && DECIMAL.test(record[key]));
  }
  assertField(
    typeof record.repository_full_name === "string" &&
      /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(record.repository_full_name),
  );
  assertField(
    typeof record.manifest_digest === "string" &&
      SHA256.test(record.manifest_digest),
  );
  assertField(typeof record.state === "string" && STATES.has(record.state));
  assertField(
    typeof record.created_at === "string" &&
      Number.isFinite(Date.parse(record.created_at)),
  );
  return {
    bountyId: record.bounty_id,
    repositoryId: record.repository_id as string,
    repositoryFullName: record.repository_full_name,
    chainId: record.chain_id as string,
    onchainBountyId: record.onchain_bounty_id as string,
    rewardAtoms: record.reward_atoms as string,
    manifestDigest: record.manifest_digest,
    state: record.state,
    createdAt: record.created_at,
    verificationProven: false,
  };
}

export class PublicBountyClient {
  private readonly endpoint: URL;

  constructor(
    supabaseUrl: string,
    private readonly serverKey: string,
    private readonly request: typeof fetch = fetch,
  ) {
    const base = new URL(supabaseUrl);
    if (
      base.protocol !== "https:" ||
      !base.hostname.endsWith(".supabase.co") ||
      base.username ||
      base.password ||
      base.search ||
      base.hash ||
      typeof serverKey !== "string" ||
      serverKey.length < 16
    ) {
      throw new Error("PUBLIC_BOUNTY_API_NOT_CONFIGURED");
    }
    this.endpoint = new URL("/rest/v1/certifiks_public_bounties_v1", base);
  }

  async list(
    limit: number,
    offset: number,
    bountyId?: string,
  ): Promise<PublicBountyV1[]> {
    if (
      !Number.isSafeInteger(limit) ||
      limit < 1 ||
      limit > 50 ||
      !Number.isSafeInteger(offset) ||
      offset < 0 ||
      offset > 10000 ||
      (bountyId !== undefined && !ID.test(bountyId))
    ) {
      throw new TypeError("PUBLIC_BOUNTY_INVALID_QUERY");
    }
    const url = new URL(this.endpoint);
    url.searchParams.set(
      "select",
      "bounty_id,repository_id,repository_full_name,chain_id,onchain_bounty_id,reward_atoms,manifest_digest,state,created_at",
    );
    url.searchParams.set("limit", String(limit));
    url.searchParams.set("offset", String(offset));
    url.searchParams.set("order", "created_at.desc,bounty_id.asc");
    if (bountyId) url.searchParams.set("bounty_id", `eq.${bountyId}`);
    let response: Response;
    try {
      response = await this.request(url.href, {
        method: "GET",
        redirect: "error",
        cache: "no-store",
        signal: AbortSignal.timeout(8000),
        headers: {
          Accept: "application/json",
          apikey: this.serverKey,
          Authorization: `Bearer ${this.serverKey}`,
        },
      });
    } catch {
      throw new Error("PUBLIC_BOUNTY_UPSTREAM_UNAVAILABLE");
    }
    if (!response.ok) throw new Error("PUBLIC_BOUNTY_UPSTREAM_UNAVAILABLE");
    let rows: unknown;
    try {
      rows = await response.json();
    } catch {
      throw new Error("PUBLIC_BOUNTY_UPSTREAM_DATA_INVALID");
    }
    assertField(Array.isArray(rows) && rows.length <= limit);
    return rows.map(parseRecord);
  }
}
