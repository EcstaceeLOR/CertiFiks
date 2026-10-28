import assert from "node:assert/strict";
import { createPublicKey, generateKeyPairSync, verify } from "node:crypto";
import test from "node:test";
import {
  GitHubAppAuthError,
  issueGitHubAppJwt,
  mintRepositoryInstallationToken,
} from "../src/github/app-auth.js";
import type { TrustedWebhookEvent } from "../src/github/webhook-auth.js";
import { PostgresWebhookJournal } from "../src/github/webhook-postgres.js";

const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const pem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
const credentials = { appId: 444, privateKeyPem: pem };
const NOW = new Date("2026-10-15T14:00:00.000Z");

test("GitHub App JWT is verifiably signed RS256 and expires within ten minutes", () => {
  const jwt = issueGitHubAppJwt(credentials, Math.floor(NOW.getTime() / 1000));
  const parts = jwt.split(".");
  assert.equal(parts.length, 3);
  const header = JSON.parse(Buffer.from(parts[0], "base64url").toString());
  const claims = JSON.parse(Buffer.from(parts[1], "base64url").toString());
  assert.equal(header.alg, "RS256");
  assert.equal(claims.iss, "444");
  assert.ok(claims.exp - claims.iat <= 600);
  assert.ok(
    verify(
      "RSA-SHA256",
      Buffer.from(parts[0] + "." + parts[1]),
      createPublicKey(privateKey),
      Buffer.from(parts[2], "base64url"),
    ),
  );
  assert.throws(() => issueGitHubAppJwt({ appId: 0, privateKeyPem: pem }));
});

function tokenResponse(
  overrides: Record<string, unknown> = {},
  status = 201,
): Response {
  return new Response(
    JSON.stringify({
      token: "github-test-token-longer-than-sixteen",
      expires_at: "2026-10-15T14:45:00.000Z",
      repositories: [{ id: 777 }],
      permissions: { contents: "read", pull_requests: "read" },
      ...overrides,
    }),
    { status, headers: { "content-type": "application/json" } },
  );
}

test("mints one-repository read-only installation token without redirects", async () => {
  let calls = 0;
  const request = (async (url: string, options?: RequestInit) => {
    calls++;
    assert.equal(
      url,
      "https://api.github.com/app/installations/555/access_tokens",
    );
    assert.equal(options?.method, "POST");
    assert.equal(options?.redirect, "error");
    assert.deepEqual(JSON.parse(String(options?.body)), {
      repository_ids: [777],
      permissions: {
        contents: "read",
        pull_requests: "read",
        metadata: "read",
      },
    });
    assert.match(
      new Headers(options?.headers).get("Authorization") ?? "",
      /^Bearer eyJ/,
    );
    return tokenResponse();
  }) as typeof fetch;
  const scoped = await mintRepositoryInstallationToken(
    credentials,
    555,
    777,
    request,
    NOW,
  );
  assert.equal(calls, 1);
  assert.equal(scoped.repositoryId, 777);
  assert.deepEqual(scoped.permissions.accessibleRepositoryIds, [777]);
});

test("rejects wrong repository, absent scopes, rejected installation and near expiry", async () => {
  for (const response of [
    tokenResponse({ repositories: [{ id: 778 }] }),
    tokenResponse({ repositories: [{ id: 777 }, { id: 778 }] }),
    tokenResponse({ permissions: { contents: "none", pull_requests: "read" } }),
    tokenResponse({ permissions: { contents: "write", pull_requests: "read" } }),
    tokenResponse({ permissions: { contents: "read", pull_requests: "write" } }),
    tokenResponse({ expires_at: "2026-10-15T14:00:30.000Z" }),
    tokenResponse({}, 403),
  ]) {
    await assert.rejects(
      mintRepositoryInstallationToken(
        credentials,
        555,
        777,
        (async () => response) as typeof fetch,
        NOW,
      ),
      GitHubAppAuthError,
    );
  }
});

const event: TrustedWebhookEvent = {
  deliveryId: "ef8547d1-b420-450c-a3ab-f976b54896ed",
  bodySha256: "ab".repeat(32),
  eventType: "pull_request",
  action: "opened",
  installationId: 555,
  repositoryId: 777,
  receivedAt: NOW.toISOString(),
  payload: {},
};

test("PostgreSQL journal sends only authenticated minimal metadata and honors duplicate result", async () => {
  const captured: string[] = [];
  const request = (async (url: string, options?: RequestInit) => {
    assert.equal(
      url,
      "https://example.supabase.co/rest/v1/rpc/certifiks_ingest_github_event",
    );
    assert.equal(
      new Headers(options?.headers).get("apikey"),
      "service-role-key-for-testing",
    );
    assert.equal(options?.redirect, "error");
    const json = JSON.parse(String(options?.body));
    assert.deepEqual(Object.keys(json).sort(), [
      "p_action",
      "p_body_sha256",
      "p_delivery_id",
      "p_event_type",
      "p_installation_id",
      "p_received_at",
      "p_repository_id",
    ]);
    captured.push(json.p_delivery_id);
    return new Response(
      JSON.stringify(captured.length === 1 ? "accepted" : "duplicate"),
      {
        status: 200,
      },
    );
  }) as typeof fetch;
  const journal = new PostgresWebhookJournal(
    "https://example.supabase.co",
    "service-role-key-for-testing",
    request,
  );
  assert.equal(await journal.record(event), "accepted");
  assert.equal(await journal.record(event), "duplicate");
});

test("database unavailable never acknowledges a delivery", async () => {
  const journal = new PostgresWebhookJournal(
    "https://example.supabase.co",
    "service-role-key-for-testing",
    (async () => new Response("denied", { status: 403 })) as typeof fetch,
  );
  await assert.rejects(journal.record(event));
});
