import { createHmac, timingSafeEqual } from "node:crypto";

const DELIVERY_ID = /^[0-9a-fA-F-]{36}$/;
const ALLOWED_EVENTS = new Set([
  "installation",
  "installation_repositories",
  "pull_request",
]);

export class GitHubWebhookError extends Error {
  constructor(
    public readonly statusCode: number,
    message: string,
  ) {
    super(message);
    this.name = "GitHubWebhookError";
  }
}

export interface TrustedWebhookEvent {
  deliveryId: string;
  eventType: string;
  action: string;
  installationId: number;
  repositoryId: number | null;
  receivedAt: string;
  payload: Record<string, unknown>;
}

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function positiveId(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}

export function authenticateGitHubWebhook(
  body: Buffer,
  signature: string | undefined,
  secret: string | undefined,
): void {
  if (!secret || secret.length < 32) {
    // Never start processing webhook events without a configured secret.
    throw new GitHubWebhookError(503, "Webhook ingestion is not configured");
  }
  if (!signature || !/^sha256=[0-9a-fA-F]{64}$/.test(signature)) {
    throw new GitHubWebhookError(401, "Missing or malformed GitHub signature");
  }
  const submitted = Buffer.from(signature.slice(7), "hex");
  const expected = createHmac("sha256", secret).update(body).digest();
  if (!timingSafeEqual(submitted, expected)) {
    throw new GitHubWebhookError(401, "Invalid GitHub webhook signature");
  }
}

export function parseTrustedGitHubWebhook(
  body: Buffer,
  headers: {
    signature?: string;
    delivery?: string;
    event?: string;
  },
  secret: string | undefined,
  now = new Date(),
): TrustedWebhookEvent {
  if (body.length === 0 || body.length > 1024 * 1024) {
    throw new GitHubWebhookError(413, "Invalid GitHub payload size");
  }
  authenticateGitHubWebhook(body, headers.signature, secret);
  const deliveryId = headers.delivery;
  if (!deliveryId || !DELIVERY_ID.test(deliveryId)) {
    throw new GitHubWebhookError(400, "Missing canonical delivery ID");
  }
  const eventType = headers.event;
  if (!eventType || !ALLOWED_EVENTS.has(eventType)) {
    throw new GitHubWebhookError(422, "GitHub event type is not supported");
  }
  let bodyValue: unknown;
  try {
    bodyValue = JSON.parse(body.toString("utf8"));
  } catch {
    throw new GitHubWebhookError(400, "Invalid GitHub event JSON");
  }
  if (!record(bodyValue)) {
    throw new GitHubWebhookError(400, "GitHub event must be an object");
  }
  const installation = bodyValue.installation;
  if (!record(installation) || !positiveId(installation.id)) {
    throw new GitHubWebhookError(422, "Missing authenticated installation identity");
  }
  const action = bodyValue.action;
  if (typeof action !== "string" || !/^[a-z_]{3,48}$/.test(action)) {
    throw new GitHubWebhookError(422, "Invalid webhook action");
  }
  const repo = bodyValue.repository;
  const repositoryId = record(repo) && positiveId(repo.id) ? repo.id : null;
  if (eventType === "pull_request") {
    const pr = bodyValue.pull_request;
    if (
      !repositoryId ||
      !record(pr) ||
      !positiveId(pr.number) ||
      !record(pr.base) ||
      !record(pr.head) ||
      typeof pr.head.sha !== "string" ||
      !/^[a-f0-9]{40}$/.test(pr.head.sha)
    ) {
      throw new GitHubWebhookError(422, "Malformed pull request identity");
    }
    if (!["opened", "reopened", "synchronize", "edited", "closed"].includes(action)) {
      throw new GitHubWebhookError(422, "Unsupported pull-request action");
    }
  } else if (eventType === "installation" && !["created", "deleted", "suspend", "unsuspend", "new_permissions_accepted"].includes(action)) {
    throw new GitHubWebhookError(422, "Unsupported installation lifecycle action");
  } else if (eventType === "installation_repositories" && !["added", "removed"].includes(action)) {
    throw new GitHubWebhookError(422, "Unsupported repository access action");
  }
  if (Number.isNaN(now.getTime())) {
    throw new GitHubWebhookError(500, "Invalid server clock");
  }
  return {
    deliveryId: deliveryId.toLowerCase(),
    eventType,
    action,
    installationId: installation.id,
    repositoryId,
    receivedAt: now.toISOString(),
    payload: bodyValue,
  };
}
