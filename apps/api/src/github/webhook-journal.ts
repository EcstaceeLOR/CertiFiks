import { mkdir, open, unlink } from "node:fs/promises";
import { join, resolve } from "node:path";
import type { TrustedWebhookEvent } from "./webhook-auth.js";

/**
 * One-process-safe, durable local ingestion journal. Atomic O_EXCL prevents
 * a delivery from being recorded twice across retries on a shared volume.
 * DO NOT use ephemeral serverless disk or separate replica disks: multi-node
 * production must replace this with a durable transactional database/queue.
 */
export class FileWebhookJournal {
  private readonly directory: string;

  constructor(directory: string) {
    if (!directory || !directory.startsWith("/")) {
      throw new Error("Webhook journal requires an absolute persistent directory");
    }
    this.directory = resolve(directory);
  }

  async record(event: TrustedWebhookEvent): Promise<"accepted" | "duplicate"> {
    if (!/^[0-9a-f-]{36}$/.test(event.deliveryId)) {
      throw new Error("Refusing unsafe delivery identifier");
    }
    await mkdir(this.directory, { recursive: true, mode: 0o700 });
    const destination = join(this.directory, event.deliveryId + ".json");
    let file;
    try {
      file = await open(destination, "wx", 0o600);
    } catch (error) {
      if (isDuplicate(error)) return "duplicate";
      throw error;
    }

    try {
      // Persist *minimum* authenticated metadata, not user-controlled PR
      // descriptions, secrets, arbitrary webhook payloads or bearer tokens.
      const record = {
        deliveryId: event.deliveryId,
        eventType: event.eventType,
        action: event.action,
        installationId: event.installationId,
        repositoryId: event.repositoryId,
        receivedAt: event.receivedAt,
        pullNumber:
          event.eventType === "pull_request" &&
          typeof event.payload.pull_request === "object" &&
          event.payload.pull_request !== null &&
          "number" in event.payload.pull_request
            ? event.payload.pull_request.number
            : null,
      };
      await file.writeFile(JSON.stringify(record) + "\n", "utf8");
      await file.sync();
    } catch (error) {
      await file.close();
      await unlink(destination).catch(() => undefined);
      throw error;
    }
    await file.close();
    return "accepted";
  }
}

function isDuplicate(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "EEXIST"
  );
}
