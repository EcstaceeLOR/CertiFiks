import Fastify from "fastify";
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
  const supabaseKey = config.supabaseServiceRoleKey ?? process.env.SUPABASE_SERVICE_ROLE_KEY;
  const production = config.production ?? process.env.NODE_ENV === "production";
  const postgresConfigured = Boolean(supabaseUrl && supabaseKey);
  const journalConfigured = postgresConfigured || (!production && Boolean(directory));

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

  return app;
}
