import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import test from "node:test";
import { GitHubAppAuthError } from "../src/github/app-auth.js";
import {
  getAuthenticatedRevisionReceiptV1,
  type VerifiedGitHubConnectionV1,
} from "../src/github/authenticated-revision.js";
import type { PinnedRevisionPolicyV1 } from "../src/github/revision-verifier.js";

const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const credentials = {
  appId: 321,
  privateKeyPem: privateKey.export({ format: "pem", type: "pkcs8" }).toString(),
};
const connection: VerifiedGitHubConnectionV1 = {
  installationId: 200,
  repositoryId: 315,
  connectedOwnerUserId: "maintainer-123",
  active: true,
  consentRecorded: true,
};
const policy: PinnedRevisionPolicyV1 = {
  repositoryId: 315,
  repositoryFullName: "owner/repository",
  pullNumber: 5,
  baseCommitSha: "a".repeat(40),
  headCommitSha: "b".repeat(40),
  developerGitHubUserId: 432,
  manifestDigest: "0x" + "11".repeat(32),
  imageDigest: "0x" + "22".repeat(32),
  allowForkPullRequests: true,
  requireVerifiedCommitSignature: true,
  baseBranch: "main",
};

test("consent-bound installation scope then immutable repo/PR/commit read yields unsigned evidence", async () => {
  const paths: string[] = [];
  const request = (async (
    url: string,
    options?: RequestInit,
  ): Promise<Response> => {
    const value = String(url);
    paths.push(value);
    const data = value.includes("/access_tokens")
      ? {
          token: "test-app-installation-token-long",
          expires_at: new Date(Date.now() + 3600_000).toISOString(),
          repositories: [{ id: 315 }],
          permissions: { contents: "read", pull_requests: "read" },
        }
      : value.endsWith("/pulls/5")
        ? {
            number: 5,
            state: "open",
            base: { sha: policy.baseCommitSha, ref: "main", repo: { id: 315 } },
            head: { sha: policy.headCommitSha, repo: { id: 999 } },
            user: { id: 432 },
          }
        : value.endsWith("/commits/" + policy.headCommitSha)
          ? {
              sha: policy.headCommitSha,
              commit: { verification: { verified: true, reason: "valid" } },
            }
          : {
              id: 315,
              full_name: "owner/repository",
              archived: false,
              disabled: false,
            };
    assert.equal(options?.redirect, "error");
    return new Response(JSON.stringify(data), {
      status: value.includes("/access_tokens") ? 201 : 200,
    });
  }) as typeof fetch;
  const receipt = await getAuthenticatedRevisionReceiptV1(
    credentials,
    connection,
    policy,
    { requestedOwnerUserId: "maintainer-123", request },
  );
  assert.equal(receipt.repositoryId, 315);
  assert.equal(receipt.installationId, 200);
  assert.match(receipt.snapshotDigest, /^0x[a-f0-9]{64}$/);
  assert.equal(paths.length, 4);
});

test("revoked, unconsented, wrong-account and wrong-repository bindings never mint tokens", async () => {
  for (const changed of [
    { ...connection, active: false },
    { ...connection, consentRecorded: false },
    { ...connection, repositoryId: 316 },
  ]) {
    await assert.rejects(
      getAuthenticatedRevisionReceiptV1(credentials, changed, policy, {
        requestedOwnerUserId: "maintainer-123",
        request: (async () => {
          throw new Error("must not access GitHub");
        }) as typeof fetch,
      }),
      GitHubAppAuthError,
    );
  }
  await assert.rejects(
    getAuthenticatedRevisionReceiptV1(credentials, connection, policy, {
      requestedOwnerUserId: "attacker-999",
      request: (async () => {
        throw new Error("must not access GitHub");
      }) as typeof fetch,
    }),
    GitHubAppAuthError,
  );
});
