/**
 * Server-only sponsor funding preparation. Never wallet-signs, broadcasts,
 * proves escrow custody, or marks a bounty funded.
 *
 * Call only after a real verified wallet/GitHub session grants sponsor
 * ownership. Do not expose the service-role key or a raw arbitrary actor ID
 * through an unauthenticated browser route.
 */
const UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const DIGEST = /^0x[a-f0-9]{64}$/;
const IDEMPOTENCY = /^[a-f0-9]{64}$/;
const NUMBER = /^[1-9][0-9]*$/;

export class SponsorFundingIntentError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SponsorFundingIntentError";
  }
}

export interface VerifiedSponsorPrincipalV1 {
  authenticatedUserId: string;
  authenticatedOrganizationId: string;
  sponsorAuthorized: boolean;
}

export interface SponsorFundingPreparationV1 {
  bountyId: string;
  manifestDigest: string;
  chainId: string;
  rewardAtoms: string;
  idempotencyDigest: string;
}

export interface PreparedSponsorFundingV1 {
  intentId: string;
  state: "prepared";
  walletSigned: false;
  fundingConfirmed: false;
  payoutAuthorized: false;
}

function fail(condition: unknown, message: string): asserts condition {
  if (!condition) throw new SponsorFundingIntentError(message);
}

function validateIdentity(principal: VerifiedSponsorPrincipalV1): void {
  fail(
    Boolean(principal) &&
      UUID.test(principal.authenticatedUserId) &&
      UUID.test(principal.authenticatedOrganizationId) &&
      principal.sponsorAuthorized === true,
    "Verified sponsor and tenant authorization required",
  );
}

function assertPositiveAtomicInteger(value: string): void {
  fail(
    typeof value === "string" && NUMBER.test(value) &&
      BigInt(value) < 2n ** 256n,
    "Only canonical decimal-string atomic units are allowed",
  );
}

export class ServerSponsorFundingIntentV1 {
  private readonly endpoint: URL;

  constructor(
    supabaseUrl: string,
    private readonly serverKey: string,
    private readonly request: typeof fetch = fetch,
  ) {
    const url = new URL(supabaseUrl);
    fail(
      url.protocol === "https:" && url.hostname.endsWith(".supabase.co") &&
      !url.username && !url.password && !url.search && !url.hash &&
      typeof serverKey === "string" && serverKey.length >= 16,
      "Server-only database credentials required",
    );
    this.endpoint = new URL("/rest/v1/rpc/", url);
  }

  private async rpc(name: string, args: object): Promise<unknown> {
    let response: Response;
    try {
      response = await this.request(new URL(name, this.endpoint).href, {
        method: "POST",
        headers: {
          apikey: this.serverKey,
          Authorization: `Bearer ${this.serverKey}`,
          "content-type": "application/json",
          Accept: "application/json",
        },
        redirect: "error",
        cache: "no-store",
        body: JSON.stringify(args),
        signal: AbortSignal.timeout(8_000),
      });
    } catch {
      throw new SponsorFundingIntentError("Funding preparation store unavailable");
    }
    if (!response.ok) throw new SponsorFundingIntentError(
      "Funding preparation rejected by immutable server policy",
    );
    try {
      return await response.json();
    } catch {
      throw new SponsorFundingIntentError("Invalid funding preparation receipt");
    }
  }

  async prepare(
    principal: VerifiedSponsorPrincipalV1,
    details: SponsorFundingPreparationV1,
  ): Promise<PreparedSponsorFundingV1> {
    validateIdentity(principal);
    fail(UUID.test(details.bountyId), "Invalid bounty identity");
    fail(DIGEST.test(details.manifestDigest) &&
      IDEMPOTENCY.test(details.idempotencyDigest),
      "Invalid immutable acceptance or idempotency digest");
    assertPositiveAtomicInteger(details.chainId);
    assertPositiveAtomicInteger(details.rewardAtoms);
    const value = await this.rpc("certifiks_prepare_sponsor_funding", {
      p_org: principal.authenticatedOrganizationId,
      p_bounty: details.bountyId,
      p_actor: principal.authenticatedUserId,
      p_manifest: details.manifestDigest,
      p_chain: details.chainId,
      p_reward: details.rewardAtoms,
      p_idempotency_digest: details.idempotencyDigest,
    });
    fail(typeof value === "string" && UUID.test(value),
      "Backend did not return canonical intent identity");
    return {
      intentId: value,
      state: "prepared",
      walletSigned: false,
      fundingConfirmed: false,
      payoutAuthorized: false,
    };
  }

  async cancel(
    principal: VerifiedSponsorPrincipalV1,
    intentId: string,
  ): Promise<boolean> {
    validateIdentity(principal);
    fail(UUID.test(intentId), "Invalid intent identity");
    const result = await this.rpc("certifiks_cancel_sponsor_funding", {
      p_intent: intentId,
      p_org: principal.authenticatedOrganizationId,
      p_actor: principal.authenticatedUserId,
    });
    fail(typeof result === "boolean", "Invalid cancellation confirmation");
    return result;
  }
}
