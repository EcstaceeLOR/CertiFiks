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

export interface AppConfiguration {
  webhookSecret?: string;
  webhookJournalDirectory?: string;
  supabaseUrl?: string;
  supabaseServiceRoleKey?: string;
  production?: boolean;
  publicBountyFetch?: typeof fetch;
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
      !(sort in PUBLIC_HISTORY_SORTS) ||
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
      !(sort in PUBLIC_HISTORY_SORTS) ||
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
        const safe = /^[=+\\-@\\t\\r]/.test(value) ? "'" + value : value;
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

  return app;
}
