import { createHash } from "node:crypto";

const TOKEN = /^cfk_[A-Za-z0-9_-]{43}$/;

export class PartnerAuthError extends Error {
  constructor(
    readonly code: "NOT_AUTHORIZED" | "UPSTREAM_UNAVAILABLE" | "MISCONFIGURED",
  ) {
    super(code);
    this.name = "PartnerAuthError";
  }
}

/**
 * Only PUBLIC finalized bounty data can be read with a partner key.
 * Enrollment, ownership, private evidence or money authorization require
 * separate session and organizational permissions.
 */
export class PartnerPublicKeyAuthorizer {
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
      url.hash ||
      url.search ||
      !serverKey ||
      serverKey.length < 16
    ) {
      throw new PartnerAuthError("MISCONFIGURED");
    }
    this.endpoint = new URL(
      "/rest/v1/rpc/certifiks_authorize_partner_key",
      url,
    ).href;
  }

  async requireBountyRead(rawKey: string | undefined): Promise<void> {
    if (typeof rawKey !== "string" || !TOKEN.test(rawKey)) {
      throw new PartnerAuthError("NOT_AUTHORIZED");
    }
    // Plaintext bearer keys are never logged, returned or transmitted to DB.
    const hash = createHash("sha256").update(rawKey, "utf8").digest("hex");
    let response: Response;
    try {
      response = await this.request(this.endpoint, {
        method: "POST",
        redirect: "error",
        cache: "no-store",
        headers: {
          apikey: this.serverKey,
          Authorization: `Bearer ${this.serverKey}`,
          "content-type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify({ p_sha256: hash, p_scope: "bounties:read" }),
        signal: AbortSignal.timeout(8000),
      });
    } catch {
      throw new PartnerAuthError("UPSTREAM_UNAVAILABLE");
    }
    if (!response.ok) throw new PartnerAuthError("UPSTREAM_UNAVAILABLE");
    let reply: unknown;
    try {
      reply = await response.json();
    } catch {
      throw new PartnerAuthError("UPSTREAM_UNAVAILABLE");
    }
    if (reply !== true) throw new PartnerAuthError("NOT_AUTHORIZED");
  }
}
