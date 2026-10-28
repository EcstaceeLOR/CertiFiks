import Fastify from "fastify";
import {
  PUBLIC_BOUNTY_STATES,
  PUBLIC_HISTORY_SORTS,
  PublicBountyClient,
  type PublicHistorySort,
} from "./bounties/public-bounties.js";
import {
  GitHubWebhookError,
  parseTrustedGitHubWebhook,
} from "./github/webhook-auth.js";
import { FileWebhookJournal } from "./github/webhook-journal.js";
import { PostgresWebhookJournal } from "./github/webhook-postgres.js";
import {
  PartnerAuthError,
  PartnerPublicKeyAuthorizer,
} from "./partners/partner-keys.js";

export interface AppConfiguration {
  webhookSecret?: string;
  webhookJournalDirectory?: string;
  supabaseUrl?: string;
  supabaseServiceRoleKey?: string;
  production?: boolean;
  publicBountyFetch?: typeof fetch;
  partnerAuthorizationFetch?: typeof fetch;
}

function oneHeader(value: string | string[] | undefined): string | undefined {
  return typeof value === "string" ? value : undefined;
}

export function buildApp(config: AppConfiguration = {}) {
  const app = Fastify({ logger: false, bodyLimit: 1024 * 1024 });
  const secret = config.webhookSecret ?? process.env.GITHUB_WEBHOOK_SECRET;
  const directory =
    config.webhookJournalDirectory ?? process.env.WEBHOOK_JOURNAL_DIR;
  const supabaseUrl = config.supabaseUrl ?? process.env.SUPABASE_URL;
  const supabaseKey =
    config.supabaseServiceRoleKey ?? process.env.SUPABASE_SERVICE_ROLE_KEY;
  const production = config.production ?? process.env.NODE_ENV === "production";
  const postgresConfigured = Boolean(supabaseUrl && supabaseKey);
  const journalConfigured =
    postgresConfigured || (!production && Boolean(directory));

  app.get("/health", async () => ({
    status: "ok",
    service: "certifiks-api",
    productReady: false,
    webhookIngestionConfigured: Boolean(secret && journalConfigured),
    note: "HTTP and webhook transport only; installation OAuth and escrow are not ready",
  }));

  // A read-only capability contract for honest onboarding/UI decisions.
  // "configured_unverified" reflects server configuration only: real chain,
  // provider, customer authentication and custody MUST be proven separately.
  app.get("/v1/capabilities", async (_request, reply) => {
    reply.header("cache-control", "no-store");
    return reply.send({
      version: "1",
      productReady: false,
      settlementReady: false,
      capabilities: {
        publicBounties: {
          state: postgresConfigured ? "configured_unverified" : "not_configured",
          readOnly: true,
        },
        githubWebhookIngestion: {
          state:
            secret && journalConfigured
              ? "configured_unverified"
              : "not_configured",
          readOnly: false,
          verifiedFix: false,
        },
        walletSignIn: { state: "not_available" },
        githubOAuth: { state: "not_available" },
        bountyFunding: { state: "not_available" },
        candidateSubmission: { state: "not_available" },
        signedVerification: { state: "not_available" },
        disputes: { state: "not_available" },
        withdrawals: { state: "not_available" },
        privateEvidence: { state: "not_available" },
      },
      note: "Server configuration is not proof of authenticated service availability, settlement finality or production readiness.",
    });
  });

  // This is a separate upstream READINESS check, not a liveness check or
  // proof of a working escrow. Never expose provider errors or credentials.
  // Production webhook delivery requires a durable PostgreSQL journal, not a
  // local filesystem. A successful public projection query verifies that the
  // configured PostgREST endpoint is currently reachable and authorized.
  app.get("/readyz", async (_request, reply) => {
    reply.header("cache-control", "no-store");
    const webhookConfigured = Boolean(
      secret && postgresConfigured && journalConfigured,
    );
    if (!webhookConfigured) {
      return reply.code(503).send({
        status: "not_ready",
        transportReady: false,
        productReady: false,
        settlementReady: false,
        checks: { publicProjection: "not_checked", webhookJournal: "blocked" },
      });
    }
    try {
      await new PublicBountyClient(
        supabaseUrl!,
        supabaseKey!,
        config.publicBountyFetch ?? fetch,
      ).list(1, 0);
      return reply.send({
        status: "ready",
        transportReady: true,
        productReady: false,
        settlementReady: false,
        checks: { publicProjection: "reachable", webhookJournal: "configured" },
      });
    } catch {
      return reply.code(503).send({
        status: "not_ready",
        transportReady: false,
        productReady: false,
        settlementReady: false,
        checks: {
          publicProjection: "unavailable",
          webhookJournal: "configured",
        },
      });
    }
  });

  // Exact raw request bytes are required for GitHub HMAC verification.
  // Never reconstruct JSON.stringify(req.body), which would change the digest.
  app.removeContentTypeParser("application/json");
  app.addContentTypeParser(
    "application/json",
    { parseAs: "buffer" },
    (_request, body, done) => done(null, body),
  );

  app.post("/webhooks/github", async (request, reply) => {
    if (!secret || !journalConfigured) {
      return reply
        .code(503)
        .send({ error: "Webhook ingestion is not configured" });
    }
    try {
      if (!Buffer.isBuffer(request.body)) {
        return reply
          .code(415)
          .send({ error: "JSON raw request bytes required" });
      }
      const event = parseTrustedGitHubWebhook(
        request.body,
        {
          signature: oneHeader(request.headers["x-hub-signature-256"]),
          delivery: oneHeader(request.headers["x-github-delivery"]),
          event: oneHeader(request.headers["x-github-event"]),
        },
        secret,
      );
      const journal = postgresConfigured
        ? new PostgresWebhookJournal(supabaseUrl!, supabaseKey!)
        : new FileWebhookJournal(directory!);
      const result = await journal.record(event);
      return reply.code(result === "accepted" ? 202 : 200).send({
        deliveryId: event.deliveryId,
        state: result === "accepted" ? "recorded" : "duplicate",
        verifiedFix: false,
      });
    } catch (error) {
      if (error instanceof GitHubWebhookError) {
        return reply.code(error.statusCode).send({ error: error.message });
      }
      // Never acknowledge unpersisted events: GitHub should retry delivery.
      request.log.error(error);
      return reply.code(503).send({ error: "Webhook journal unavailable" });
    }
  });

  // Read-only, opt-in PUBLIC metadata. No private artifacts or unverified
  // funding data are returned, and no fallback mock data exist.
  app.get("/v1/bounties", async (request, reply) => {
    if (!postgresConfigured) {
      return reply
        .code(503)
        .send({ error: "PUBLIC_BOUNTY_API_NOT_CONFIGURED" });
    }
    const query = request.query as Record<string, unknown>;
    if (
      !Object.keys(query).every((key) =>
        ["limit", "offset", "state", "repo", "sort"].includes(key),
      )
    ) {
      return reply.code(400).send({ error: "PUBLIC_BOUNTY_INVALID_FILTER" });
    }
    const parsePage = (value: unknown, fallback: number): number | null => {
      if (value === undefined) return fallback;
      if (typeof value !== "string" || !/^(0|[1-9][0-9]*)$/.test(value))
        return null;
      const number = Number(value);
      return Number.isSafeInteger(number) ? number : null;
    };
    const limit = parsePage(query.limit, 20);
    const offset = parsePage(query.offset, 0);
    if (
      limit === null ||
      limit < 1 ||
      limit > 50 ||
      offset === null ||
      offset > 10000
    ) {
      return reply.code(400).send({ error: "PUBLIC_BOUNTY_INVALID_QUERY" });
    }
    // Only exact published state/repository match is accepted. Filtering must
    // happen inside the private finalized-only PostgREST view *before* paging.
    const state = query.state;
    const repositoryFullName = query.repo;
    const sort = query.sort ?? "newest";
    if (
      typeof sort !== "string" ||
      !Object.hasOwn(PUBLIC_HISTORY_SORTS, sort) ||
      (state !== undefined &&
        (typeof state !== "string" || !PUBLIC_BOUNTY_STATES.has(state))) ||
      (repositoryFullName !== undefined &&
        (typeof repositoryFullName !== "string" ||
          !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repositoryFullName)))
    ) {
      return reply.code(400).send({ error: "PUBLIC_BOUNTY_INVALID_FILTER" });
    }
    try {
      const items = await new PublicBountyClient(
        supabaseUrl!,
        supabaseKey!,
        config.publicBountyFetch ?? fetch,
      ).list(limit, offset, undefined, {
        state: state as string | undefined,
        repositoryFullName: repositoryFullName as string | undefined,
        sort: sort as PublicHistorySort,
      });
      return reply.send({
        items,
        page: {
          limit,
          offset,
          nextOffset: items.length === limit ? offset + limit : null,
        },
        note: "Publication is not independent proof of bug verification or payment.",
      });
    } catch {
      return reply
        .code(503)
        .send({ error: "PUBLIC_BOUNTY_UPSTREAM_UNAVAILABLE" });
    }
  });

  // Download only a single bounded PUBLIC page. Never private org dashboards,
  // addresses, custody balance, confidential evidence or speculative metrics.
  app.get("/v1/bounties/export.csv", async (request, reply) => {
    if (!postgresConfigured) {
      return reply
        .code(503)
        .send({ error: "PUBLIC_BOUNTY_API_NOT_CONFIGURED" });
    }
    const query = request.query as Record<string, unknown>;
    if (
      !Object.keys(query).every((key) =>
        ["offset", "state", "repo", "sort"].includes(key),
      )
    ) {
      return reply.code(400).send({ error: "PUBLIC_BOUNTY_INVALID_FILTER" });
    }
    const parseOffset = (value: unknown): number | null => {
      if (value === undefined) return 0;
      if (typeof value !== "string" || !/^(0|[1-9][0-9]*)$/.test(value))
        return null;
      const parsed = Number(value);
      return Number.isSafeInteger(parsed) && parsed <= 10000 ? parsed : null;
    };
    const offset = parseOffset(query.offset);
    const state = query.state;
    const repo = query.repo;
    const sort = query.sort ?? "newest";
    if (
      offset === null ||
      (state !== undefined &&
        (typeof state !== "string" || !PUBLIC_BOUNTY_STATES.has(state))) ||
      (repo !== undefined &&
        (typeof repo !== "string" ||
          !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo))) ||
      typeof sort !== "string" ||
      !Object.hasOwn(PUBLIC_HISTORY_SORTS, sort) ||
      query.limit !== undefined
    ) {
      return reply.code(400).send({ error: "PUBLIC_BOUNTY_INVALID_FILTER" });
    }
    try {
      const records = await new PublicBountyClient(
        supabaseUrl!,
        supabaseKey!,
        config.publicBountyFetch ?? fetch,
      ).list(50, offset, undefined, {
        state: state as string | undefined,
        repositoryFullName: repo as string | undefined,
        sort: sort as PublicHistorySort,
      });
      const quote = (value: string) => {
        // CSV fields can begin with "-" even when repository names validate.
        // Prevent spreadsheet formula interpretation without changing numeric precision.
        const dangerousPrefix =
          ["=", "+", "-", "@"].some((prefix) => value.startsWith(prefix)) ||
          value.charCodeAt(0) === 9 ||
          value.charCodeAt(0) === 13;
        const safe = dangerousPrefix ? "'" + value : value;
        return '"' + safe.replaceAll('"', '""') + '"';
      };
      const lines = [
        "bounty_id,repository,state,created_at,chain_id,onchain_bounty_id,reward_atoms,manifest_digest,verified_fix",
        ...records.map((item) =>
          [
            item.bountyId,
            item.repositoryFullName,
            item.state,
            item.createdAt,
            item.chainId,
            item.onchainBountyId,
            item.rewardAtoms,
            item.manifestDigest,
            "false",
          ]
            .map(quote)
            .join(","),
        ),
      ];
      return reply
        .header("content-type", "text/csv; charset=utf-8")
        .header("cache-control", "no-store")
        .header(
          "content-disposition",
          'attachment; filename="certifiks-public-history.csv"',
        )
        .send(lines.join("\r\n") + "\r\n");
    } catch {
      return reply
        .code(503)
        .send({ error: "PUBLIC_BOUNTY_UPSTREAM_UNAVAILABLE" });
    }
  });

  app.get("/v1/bounties/:bountyId", async (request, reply) => {
    if (!postgresConfigured) {
      return reply
        .code(503)
        .send({ error: "PUBLIC_BOUNTY_API_NOT_CONFIGURED" });
    }
    const { bountyId } = request.params as { bountyId: string };
    if (Object.keys(request.query as Record<string, unknown>).length !== 0) {
      return reply.code(400).send({ error: "PUBLIC_BOUNTY_INVALID_QUERY" });
    }
    if (!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/.test(bountyId)) {
      return reply.code(400).send({ error: "PUBLIC_BOUNTY_INVALID_ID" });
    }
    try {
      const records = await new PublicBountyClient(
        supabaseUrl!,
        supabaseKey!,
        config.publicBountyFetch ?? fetch,
      ).list(1, 0, bountyId);
      return records[0]
        ? reply.send(records[0])
        : reply.code(404).send({ error: "PUBLIC_BOUNTY_NOT_FOUND" });
    } catch {
      return reply
        .code(503)
        .send({ error: "PUBLIC_BOUNTY_UPSTREAM_UNAVAILABLE" });
    }
  });

  // Partner API keys are only a scoped, revocable front door to the exact same
  // FINALIZED-only PUBLIC projection. A key cannot retrieve private evidence,
  // tenant billing, wallet custody or organization members.
  app.get("/v1/partner/bounties", async (request, reply) => {
    reply.header("cache-control", "no-store");
    reply.header("vary", "x-certifiks-api-key");
    if (!postgresConfigured) {
      return reply.code(503).send({ error: "PARTNER_API_NOT_CONFIGURED" });
    }
    try {
      await new PartnerPublicKeyAuthorizer(
        supabaseUrl!,
        supabaseKey!,
        config.partnerAuthorizationFetch ?? fetch,
      ).requireBountyRead(oneHeader(request.headers["x-certifiks-api-key"]));
    } catch (error) {
      if (
        error instanceof PartnerAuthError &&
        error.code === "NOT_AUTHORIZED"
      ) {
        return reply.code(401).send({ error: "PARTNER_NOT_AUTHORIZED" });
      }
      return reply.code(503).send({ error: "PARTNER_AUTH_UNAVAILABLE" });
    }

    const query = request.query as Record<string, unknown>;
    if (
      Object.keys(query).some(
        (key) => !["limit", "offset", "state", "repo", "sort"].includes(key),
      )
    ) {
      return reply.code(400).send({ error: "PARTNER_INVALID_FILTER" });
    }
    const parsePage = (value: unknown, fallback: number) => {
      if (value === undefined) return fallback;
      if (typeof value !== "string" || !/^(0|[1-9][0-9]*)$/.test(value))
        return null;
      const parsed = Number(value);
      return Number.isSafeInteger(parsed) ? parsed : null;
    };
    const limit = parsePage(query.limit, 20);
    const offset = parsePage(query.offset, 0);
    const state = query.state;
    const repo = query.repo;
    const sort = query.sort ?? "newest";
    if (
      limit === null ||
      limit < 1 ||
      limit > 50 ||
      offset === null ||
      offset > 10000 ||
      (state !== undefined &&
        (typeof state !== "string" || !PUBLIC_BOUNTY_STATES.has(state))) ||
      (repo !== undefined &&
        (typeof repo !== "string" ||
          !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo))) ||
      typeof sort !== "string" ||
      !Object.hasOwn(PUBLIC_HISTORY_SORTS, sort)
    )
      return reply.code(400).send({ error: "PARTNER_INVALID_FILTER" });

    try {
      const items = await new PublicBountyClient(
        supabaseUrl!,
        supabaseKey!,
        config.publicBountyFetch ?? fetch,
      ).list(limit, offset, undefined, {
        state: state as string | undefined,
        repositoryFullName: repo as string | undefined,
        sort: sort as PublicHistorySort,
      });
      return reply.send({
        items,
        page: {
          limit,
          offset,
          nextOffset: items.length === limit ? offset + limit : null,
        },
        verificationProven: false,
        note: "Public finalized-index metadata only; no private evidence or confirmed payouts.",
      });
    } catch {
      return reply.code(503).send({ error: "PARTNER_UPSTREAM_UNAVAILABLE" });
    }
  });

  return app;
}
