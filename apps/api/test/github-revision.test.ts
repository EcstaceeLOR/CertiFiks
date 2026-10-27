import assert from "node:assert/strict";
import test from "node:test";
import {
  fetchGitHubRevisionSnapshotV1,
  GitHubRevisionError,
  type GitHubSnapshotV1,
  type InstalledRepositoryPermissionsV1,
  type PinnedRevisionPolicyV1,
  verifyGitHubRevisionSnapshotV1,
} from "../src/github/revision-verifier.js";

const policy: PinnedRevisionPolicyV1 = {
  repositoryId: 314159,
  repositoryFullName: "maintainer/fix-target",
  pullNumber: 18,
  baseCommitSha: "a".repeat(40),
  headCommitSha: "b".repeat(40),
  developerGitHubUserId: 424242,
  manifestDigest: "0x" + "11".repeat(32),
  imageDigest: "0x" + "22".repeat(32),
  allowForkPullRequests: true,
  requireVerifiedCommitSignature: true,
  baseBranch: "main",
};

const access: InstalledRepositoryPermissionsV1 = {
  installationId: 555,
  accessibleRepositoryIds: [314159],
  granted: { contents: "read", pull_requests: "read" },
};

const snapshot: GitHubSnapshotV1 = {
  repo: {
    id: 314159,
    full_name: "maintainer/fix-target",
    archived: false,
    disabled: false,
  },
  pull: {
    number: 18,
    state: "open",
    base: { sha: "a".repeat(40), ref: "main", repo: { id: 314159 } },
    head: { sha: "b".repeat(40), repo: { id: 161803 } },
    user: { id: 424242 },
  },
  commit: {
    sha: "b".repeat(40),
    commit: { verification: { verified: true, reason: "valid" } },
  },
};

const deep = <T>(value: T): T => structuredClone(value);

function fails(body: () => unknown, code: GitHubRevisionError["code"]): void {
  assert.throws(
    body,
    (error: unknown) =>
      error instanceof GitHubRevisionError && error.code === code,
  );
}

test("exact authenticated snapshot produces repeatable evidence digest", () => {
  const receipt = verifyGitHubRevisionSnapshotV1(policy, access, snapshot);
  assert.equal(receipt.pullNumber, 18);
  assert.equal(receipt.repositoryId, 314159);
  assert.equal(receipt.baseBranch, "main");
  assert.equal(receipt.fork, true);
  assert.equal(receipt.sourceRepositoryId, 161803);
  assert.equal(receipt.commitSignatureVerified, true);
  assert.match(receipt.snapshotDigest, /^0x[a-f0-9]{64}$/);
  assert.equal(
    receipt.snapshotDigest,
    verifyGitHubRevisionSnapshotV1(policy, access, snapshot).snapshotDigest,
  );
});

test("wrong numeric repo ID blocks renamed lookalike owner/path", () => {
  const fake = deep(snapshot);
  fake.repo.id = 999;
  fails(
    () => verifyGitHubRevisionSnapshotV1(policy, access, fake),
    "STALE_COMMIT",
  );
  fake.repo.id = 314159;
  fake.pull.base.repo.id = 999;
  fails(
    () => verifyGitHubRevisionSnapshotV1(policy, access, fake),
    "STALE_COMMIT",
  );
});

test("renamed/transferred repo requires a new approved funded manifest", () => {
  const moved = deep(snapshot);
  moved.repo.full_name = "new-org/fix-target";
  fails(
    () => verifyGitHubRevisionSnapshotV1(policy, access, moved),
    "MANIFEST_MISMATCH",
  );
  const differentPolicy = {
    ...policy,
    repositoryFullName: moved.repo.full_name,
  };
  const a = verifyGitHubRevisionSnapshotV1(differentPolicy, access, moved);
  assert.equal(a.repositoryId, 314159);
  assert.notEqual(
    a.snapshotDigest,
    verifyGitHubRevisionSnapshotV1(policy, access, snapshot).snapshotDigest,
  );
});

test("stale force-push or rebased baseline cannot substitute committed revision", () => {
  const forcePushed = deep(snapshot);
  forcePushed.pull.head.sha = "c".repeat(40);
  fails(
    () => verifyGitHubRevisionSnapshotV1(policy, access, forcePushed),
    "STALE_COMMIT",
  );
  const rebased = deep(snapshot);
  rebased.pull.base.sha = "d".repeat(40);
  fails(
    () => verifyGitHubRevisionSnapshotV1(policy, access, rebased),
    "STALE_COMMIT",
  );
});

test("PR retargeting to another base branch is rejected even if SHAs match", () => {
  const retargeted = deep(snapshot);
  retargeted.pull.base.ref = "dev";
  fails(
    () => verifyGitHubRevisionSnapshotV1(policy, access, retargeted),
    "STALE_COMMIT",
  );
  fails(
    () =>
      verifyGitHubRevisionSnapshotV1(
        { ...policy, baseBranch: "../secrets" },
        access,
        snapshot,
      ),
    "INVALID_SCHEMA",
  );
});

test("commit endpoint hash is independently compared, not only the PR label", () => {
  const changed = deep(snapshot);
  changed.commit.sha = "c".repeat(40);
  fails(
    () => verifyGitHubRevisionSnapshotV1(policy, access, changed),
    "STALE_COMMIT",
  );
});

test("PR author must correspond to developer bound to accepted wallet", () => {
  const fake = deep(snapshot);
  fake.pull.user = { id: 9999 };
  fails(
    () => verifyGitHubRevisionSnapshotV1(policy, access, fake),
    "UNAUTHORIZED",
  );
  fake.pull.user = null;
  fails(
    () => verifyGitHubRevisionSnapshotV1(policy, access, fake),
    "UNAUTHORIZED",
  );
});

test("fork PR behavior is pinned to sponsor policy and source repository ID", () => {
  fails(
    () =>
      verifyGitHubRevisionSnapshotV1(
        { ...policy, allowForkPullRequests: false },
        access,
        snapshot,
      ),
    "FORBIDDEN",
  );
  const originalRepo = deep(snapshot);
  originalRepo.pull.head.repo = { id: 314159 };
  const result = verifyGitHubRevisionSnapshotV1(
    { ...policy, allowForkPullRequests: false },
    access,
    originalRepo,
  );
  assert.equal(result.fork, false);
  assert.notEqual(
    result.snapshotDigest,
    verifyGitHubRevisionSnapshotV1(policy, access, snapshot).snapshotDigest,
  );
  originalRepo.pull.head.repo = null;
  fails(
    () => verifyGitHubRevisionSnapshotV1(policy, access, originalRepo),
    "STALE_COMMIT",
  );
});

test("verified commit signature policy fails closed", () => {
  const unsigned = deep(snapshot);
  unsigned.commit.commit.verification.verified = false;
  fails(
    () => verifyGitHubRevisionSnapshotV1(policy, access, unsigned),
    "FORBIDDEN",
  );
  const permissive = verifyGitHubRevisionSnapshotV1(
    { ...policy, requireVerifiedCommitSignature: false },
    access,
    unsigned,
  );
  assert.equal(permissive.commitSignatureVerified, false);
});

test("installation requires actual repository scope and app read grants", () => {
  fails(
    () =>
      verifyGitHubRevisionSnapshotV1(
        policy,
        { ...access, installationId: 0 },
        snapshot,
      ),
    "UNAUTHORIZED",
  );
  fails(
    () =>
      verifyGitHubRevisionSnapshotV1(
        policy,
        { ...access, accessibleRepositoryIds: [] },
        snapshot,
      ),
    "FORBIDDEN",
  );
  fails(
    () =>
      verifyGitHubRevisionSnapshotV1(
        policy,
        { ...access, granted: { contents: "none", pull_requests: "read" } },
        snapshot,
      ),
    "FORBIDDEN",
  );
  fails(
    () =>
      verifyGitHubRevisionSnapshotV1(
        policy,
        { ...access, granted: { contents: "read", pull_requests: "none" } },
        snapshot,
      ),
    "FORBIDDEN",
  );
});

test("PR number/state and archived repository must all match", () => {
  const v = deep(snapshot);
  v.pull.number = 19;
  fails(
    () => verifyGitHubRevisionSnapshotV1(policy, access, v),
    "STALE_COMMIT",
  );
  v.pull.number = 18;
  v.pull.state = "closed";
  fails(
    () => verifyGitHubRevisionSnapshotV1(policy, access, v),
    "STALE_COMMIT",
  );
  v.pull.state = "open";
  v.repo.archived = true;
  fails(() => verifyGitHubRevisionSnapshotV1(policy, access, v), "FORBIDDEN");
});

test("SHA-1 fields, safe integer IDs and policy hashes require strict form", () => {
  fails(
    () =>
      verifyGitHubRevisionSnapshotV1(
        { ...policy, headCommitSha: "B".repeat(40) },
        access,
        snapshot,
      ),
    "INVALID_SCHEMA",
  );
  fails(
    () =>
      verifyGitHubRevisionSnapshotV1(
        { ...policy, repositoryId: 1e30 },
        access,
        snapshot,
      ),
    "INVALID_SCHEMA",
  );
  fails(
    () =>
      verifyGitHubRevisionSnapshotV1(
        { ...policy, pullNumber: 0 },
        access,
        snapshot,
      ),
    "INVALID_SCHEMA",
  );
  fails(
    () =>
      verifyGitHubRevisionSnapshotV1(
        { ...policy, manifestDigest: "0x0" },
        access,
        snapshot,
      ),
    "INVALID_SCHEMA",
  );
  fails(
    () =>
      verifyGitHubRevisionSnapshotV1(
        { ...policy, repositoryFullName: "../evil" },
        access,
        snapshot,
      ),
    "INVALID_SCHEMA",
  );
});

test("read-only GitHub requests use fixed API host, authenticated installation token and no redirects", async () => {
  const calls: { url: string; auth?: string; redirect?: RequestRedirect }[] =
    [];
  const fakeFetch = (async (url: string, options?: RequestInit) => {
    const s = String(url);
    calls.push({
      url: s,
      auth: new Headers(options?.headers).get("Authorization") || undefined,
      redirect: options?.redirect,
    });
    const payload = s.endsWith("/pulls/18")
      ? snapshot.pull
      : s.endsWith("/commits/" + policy.headCommitSha)
        ? snapshot.commit
        : snapshot.repo;
    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }) as typeof fetch;

  const output = await fetchGitHubRevisionSnapshotV1(
    policy,
    "fake-installation-secret-for-test",
    fakeFetch,
  );
  const proof = verifyGitHubRevisionSnapshotV1(policy, access, output);
  assert.equal(proof.headCommitSha, policy.headCommitSha);
  assert.equal(calls.length, 3);
  for (const c of calls) {
    assert.ok(
      c.url.startsWith("https://api.github.com/repos/maintainer/fix-target"),
    );
    assert.equal(c.auth, "Bearer fake-installation-secret-for-test");
    assert.equal(c.redirect, "error");
  }
});

test("GitHub access failures are not treated as a verified PR", async () => {
  const denied = (async () =>
    new Response("no", { status: 403 })) as typeof fetch;
  await assert.rejects(
    () => fetchGitHubRevisionSnapshotV1(policy, "secret-secret", denied),
    (e: unknown) => e instanceof GitHubRevisionError && e.code === "FORBIDDEN",
  );
  const expired = (async () =>
    new Response("no", { status: 401 })) as typeof fetch;
  await assert.rejects(
    () => fetchGitHubRevisionSnapshotV1(policy, "secret-secret", expired),
    (e: unknown) =>
      e instanceof GitHubRevisionError && e.code === "UNAUTHORIZED",
  );
  await assert.rejects(
    () => fetchGitHubRevisionSnapshotV1(policy, "", expired),
    (e: unknown) =>
      e instanceof GitHubRevisionError && e.code === "UNAUTHORIZED",
  );
});

test("a numeric ID match never licenses arbitrary sponsor policy changes", () => {
  const changedPolicy = { ...policy, imageDigest: "0x" + "bb".repeat(32) };
  const proof = verifyGitHubRevisionSnapshotV1(policy, access, snapshot);
  const changed = verifyGitHubRevisionSnapshotV1(
    changedPolicy,
    access,
    snapshot,
  );
  assert.notEqual(proof.snapshotDigest, changed.snapshotDigest);
  assert.equal(changed.manifestDigest, proof.manifestDigest);
});
