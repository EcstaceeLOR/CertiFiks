import assert from "node:assert/strict";
import { createHmac, randomUUID } from "node:crypto";
import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { buildApp } from "../src/app.js";

const SECRET = "github-integration-secret-with-at-least-32-characters";
const INSTALLATION_ID = 801;
const REPOSITORY_ID = 987;

function payload(event: string, action: string): Record<string, unknown> {
  const common = {
    action,
    installation: { id: INSTALLATION_ID },
    repository: { id: REPOSITORY_ID },
  };
  if (event === "pull_request") {
    return {
      ...common,
      pull_request: {
        number: 12,
        head: { sha: "a".repeat(40) },
        base: { sha: "b".repeat(40) },
      },
    };
  }
  return common;
}

function request(
  event: string,
  action: string,
  options: { delivery?: string; body?: string; secret?: string } = {},
) {
  const body = options.body ?? JSON.stringify(payload(event, action));
  const signature = createHmac("sha256", options.secret ?? SECRET)
    .update(body)
    .digest("hex");
  return {
    method: "POST" as const,
    url: "/webhooks/github",
    headers: {
      "content-type": "application/json",
      "x-github-event": event,
      "x-github-delivery": options.delivery ?? randomUUID(),
      "x-hub-signature-256": "sha256=" + signature,
    },
    payload: body,
  };
}

test("forged event fails authentication without durable side effects", async () => {
  const directory = await mkdtemp(join(tmpdir(), "certifiks-webhooks-"));
  const app = buildApp({
    webhookSecret: SECRET,
    webhookJournalDirectory: directory,
  });
  try {
    const forged = await app.inject(
      request("pull_request", "opened", { secret: "wrong-secret" }),
    );
    assert.equal(forged.statusCode, 401);
    assert.deepEqual(await readdir(directory), []);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("signed pull request is persisted once, even under concurrent deliveries", async () => {
  const directory = await mkdtemp(join(tmpdir(), "certifiks-webhooks-"));
  const app = buildApp({
    webhookSecret: SECRET,
    webhookJournalDirectory: directory,
  });
  const delivery = randomUUID();
  try {
    const [first, second] = await Promise.all([
      app.inject(request("pull_request", "opened", { delivery })),
      app.inject(request("pull_request", "opened", { delivery })),
    ]);
    assert.deepEqual(
      [first.statusCode, second.statusCode].sort(),
      [200, 202],
    );
    const files = await readdir(directory);
    assert.deepEqual(files, [delivery + ".json"]);
    const entry = JSON.parse(
      await readFile(join(directory, files[0]), "utf8"),
    );
    assert.equal(entry.repositoryId, REPOSITORY_ID);
    assert.equal(entry.installationId, INSTALLATION_ID);
    assert.equal(entry.pullNumber, 12);
    assert.equal("payload" in entry, false);
    assert.equal(first.json().verifiedFix, false);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("installation revocation and access removals are journaled", async () => {
  const directory = await mkdtemp(join(tmpdir(), "certifiks-webhooks-"));
  const app = buildApp({
    webhookSecret: SECRET,
    webhookJournalDirectory: directory,
  });
  try {
    for (const [event, action] of [
      ["installation", "deleted"],
      ["installation_repositories", "removed"],
      ["installation", "suspend"],
    ]) {
      const response = await app.inject(request(event, action));
      assert.equal(response.statusCode, 202);
    }
    assert.equal((await readdir(directory)).length, 3);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("expired installation access, malformed and unsupported PR events fail closed", async () => {
  const directory = await mkdtemp(join(tmpdir(), "certifiks-webhooks-"));
  const app = buildApp({
    webhookSecret: SECRET,
    webhookJournalDirectory: directory,
  });
  try {
    const badInstallation = JSON.stringify({
      ...payload("pull_request", "opened"),
      installation: { id: 0 },
    });
    assert.equal(
      (await app.inject(request("pull_request", "opened", { body: badInstallation }))).statusCode,
      422,
    );
    assert.equal(
      (await app.inject(request("pull_request", "opened", { body: "{invalid" }))).statusCode,
      400,
    );
    assert.equal(
      (await app.inject(request("push", "created"))).statusCode,
      422,
    );
    assert.deepEqual(await readdir(directory), []);
  } finally {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("no configured durable storage or webhook secret means HTTP 503", async () => {
  const app = buildApp({
    webhookSecret: SECRET,
    webhookJournalDirectory: "",
  });
  try {
    const response = await app.inject(request("pull_request", "opened"));
    assert.equal(response.statusCode, 503);
  } finally {
    await app.close();
  }
});
