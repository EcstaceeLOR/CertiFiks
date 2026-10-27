import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import test from "node:test";
import { GitHubAppAuthError } from "../src/github/app-auth.js";
import {
  captureAuthenticatedGitHubAttemptV1,
  GitHubReceiptPersistenceError,
} from "../src/github/attempt-receipt-store.js";
import type { PinnedRevisionPolicyV1 } from "../src/github/revision-verifier.js";

const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const credentials = {
  appId: 55,
  privateKeyPem: privateKey.export({ format: "pem", type: "pkcs8" }).toString(),
};
const policy: PinnedRevisionPolicyV1 = {
  repositoryId: 401,
  repositoryFullName: "sponsor-a/bugfix",
  pullNumber: 10,
  baseCommitSha: "b".repeat(40),
  headCommitSha: "c".repeat(40),
  developerGitHubUserId: 4567,
  manifestDigest: `0x${"a".repeat(64)}`,
  imageDigest: `0x${"e".repeat(64)}`,
  allowForkPullRequests: true,
  requireVerifiedCommitSignature: false,
  baseBranch: "main",
};
const connection = {
  installationId: 1234,
  repositoryId: 401,
  connectedOwnerUserId: "trusted-maintainer",
  active: true,
  consentRecorded: true,
};
const context = {
  organizationId: "20000000-0000-4000-8000-000000000001",
  bountyId: "30000000-0000-4000-8000-000000000001",
  attemptId: "60000000-0000-4000-8000-000000000001",
  authenticatedOwnerUserId: "trusted-maintainer",
};
const serviceRoleKey = "synthetic-service-role-token-not-real";

function stubGitHub(requests: string[]) {
  return (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    requests.push(url);
    assert.equal(init?.redirect, "error");
    const data = url.includes("/access_tokens")
      ? {
          token: "synthetic-scoped-installation-token",
          expires_at: new Date(Date.now() + 3600000).toISOString(),
          repositories: [{ id: policy.repositoryId }],
          permissions: { contents: "read", pull_requests: "read" },
        }
      : url.endsWith("/pulls/10")
        ? {
            number: 10,
            state: "open",
            base: {
              sha: policy.baseCommitSha,
              ref: "main",
              repo: { id: policy.repositoryId },
            },
            head: { sha: policy.headCommitSha, repo: { id: 999 } },
            user: { id: 4567 },
          }
        : url.endsWith(`/commits/${policy.headCommitSha}`)
          ? {
              sha: policy.headCommitSha,
              commit: { verification: { verified: false, reason: "unsigned" } },
            }
          : {
              id: 401,
              full_name: "sponsor-a/bugfix",
              archived: false,
              disabled: false,
            };
    return new Response(JSON.stringify(data), {
      status: url.includes("/access_tokens") ? 201 : 200,
    });
  }) as typeof fetch;
}

test("authenticated app snapshot is inserted exactly once with fork and fixed identities", async () => {
  const githubPaths: string[] = [];
  let dbCalls = 0;
  const receipt = await captureAuthenticatedGitHubAttemptV1(
    credentials,
    connection,
    policy,
    context,
    {
      supabaseUrl: "https://certifiks-ci.supabase.co",
      serviceRoleKey,
      request: (async (input: RequestInfo | URL, init?: RequestInit) => {
        dbCalls += 1;
        assert.equal(
          String(input),
          "https://certifiks-ci.supabase.co/rest/v1/certifiks_github_revision_receipts",
        );
        assert.equal(init?.method, "POST");
        assert.equal(init?.redirect, "error");
        assert.equal(init?.cache, "no-store");
        assert.equal(
          (init?.headers as Record<string, string> | undefined)?.apikey,
          serviceRoleKey,
        );
        const json = JSON.parse(String(init?.body));
        assert.equal(json.organization_id, context.organizationId);
        assert.equal(json.attempt_id, context.attemptId);
        assert.equal(json.repository_id, 401);
        assert.equal(json.source_repository_id, 999);
        assert.equal(json.fork, true);
        assert.equal(json.base_commit_sha, policy.baseCommitSha);
        assert.equal(json.head_commit_sha, policy.headCommitSha);
        assert.equal(json.manifest_digest, policy.manifestDigest);
        assert.match(json.snapshot_digest, /^0x[a-f0-9]{64}$/);
        assert.equal("token" in json, false);
        return new Response(null, { status: 201 });
      }) as typeof fetch,
    },
    stubGitHub(githubPaths),
  );
  assert.equal(githubPaths.length, 4);
  assert.equal(dbCalls, 1);
  assert.equal(receipt.sourceRepositoryId, 999);
});

test("database failure or replay never gets reported as admitted evidence", async () => {
  for (const status of [409, 401, 503]) {
    await assert.rejects(
      captureAuthenticatedGitHubAttemptV1(
        credentials,
        connection,
        policy,
        context,
        {
          supabaseUrl: "https://certifiks-ci.supabase.co",
          serviceRoleKey,
          request: (async () => new Response(null, { status })) as typeof fetch,
        },
        stubGitHub([]),
      ),
      (error: unknown) =>
        error instanceof GitHubReceiptPersistenceError &&
        error.code === (status === 409 ? "ALREADY_PINNED" : "PERSISTENCE_UNAVAILABLE"),
    );
  }
});

test("invalid storage origin or tenant fields refuse all upstream calls", async () => {
  for (const params of [
    {
      context,
      url: "https://attacker.invalid",
    },
    {
      context: { ...context, attemptId: "bad" },
      url: "https://certifiks-ci.supabase.co",
    },
  ]) {
    await assert.rejects(
      captureAuthenticatedGitHubAttemptV1(
        credentials,
        connection,
        policy,
        params.context,
        {
          supabaseUrl: params.url,
          serviceRoleKey,
          request: (async () => {
            throw new Error("must not persist anything");
          }) as typeof fetch,
        },
        (async () => {
          throw new Error("must not mint or query GitHub");
        }) as typeof fetch,
      ),
      GitHubReceiptPersistenceError,
    );
  }
});

test("revoked consent or forged owner cannot persist any submitted revision", async () => {
  let writes = 0;
  for (const options of [
    { ...connection, consentRecorded: false },
    { ...connection, repositoryId: 999 },
  ]) {
    await assert.rejects(
      captureAuthenticatedGitHubAttemptV1(
        credentials,
        options,
        policy,
        context,
        {
          supabaseUrl: "https://certifiks-ci.supabase.co",
          serviceRoleKey,
          request: (async () => {
            writes += 1;
            return new Response(null, { status: 201 });
          }) as typeof fetch,
        },
        stubGitHub([]),
      ),
      GitHubAppAuthError,
    );
  }
  assert.equal(writes, 0);
});
