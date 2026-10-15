import type { TrustedWebhookEvent } from "./webhook-auth.js";

export class PostgresWebhookJournal {
  private readonly endpoint: string;

  constructor(
    supabaseUrl: string,
    private readonly serverKey: string,
    private readonly request: typeof fetch = fetch,
  ) {
    const url = new URL(supabaseUrl);
    if (
      url.protocol !== "https:" ||
      url.username ||
      url.password ||
      url.search ||
      url.hash
    ) {
      throw new Error(
        "Transactional webhook journal requires clean HTTPS Supabase URL",
      );
    }
    if (!serverKey || serverKey.length < 16)
      throw new Error("Service role key missing");
    this.endpoint = new URL(
      "/rest/v1/rpc/certifiks_ingest_github_event",
      url,
    ).href;
  }

  async record(event: TrustedWebhookEvent): Promise<"accepted" | "duplicate"> {
    // Database does atomic deduplication and queue insertion in ONE transaction;
    // no success is returned until durable RPC confirmation is received.
    const reply = await this.request(this.endpoint, {
      method: "POST",
      redirect: "error",
      cache: "no-store",
      headers: {
        apikey: this.serverKey,
        Authorization: `Bearer ${this.serverKey}`,
        "content-type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        p_delivery_id: event.deliveryId,
        p_body_sha256: event.bodySha256,
        p_event_type: event.eventType,
        p_action: event.action,
        p_installation_id: event.installationId,
        p_repository_id: event.repositoryId,
        p_received_at: event.receivedAt,
      }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!reply.ok) throw new Error("Transactional webhook journal unavailable");
    const result: unknown = await reply.json();
    if (result !== "accepted" && result !== "duplicate") {
      throw new Error(
        "Transactional webhook journal returned invalid confirmation",
      );
    }
    return result;
  }
}
