import assert from "node:assert/strict";
import test from "node:test";
import {
  prepareGitHubCheckV1,
  type TrustedQualificationV1,
} from "../src/partners/github-check-plan.js";

const base: TrustedQualificationV1 = {
  repositoryFullName: "trusted/real-repo",
  repositoryId: "22",
  attemptId: "10",
  headCommitSha: "a".repeat(40),
  state: "pending",
  reportDigest: null,
  independentlyQualified: false,
  trustedQuorum: false,
  artifactIntegrity: false,
};

test("pending and inconclusive never impersonate a verified fix or payment", () => {
  const pending = prepareGitHubCheckV1(base);
  assert.equal(pending.status, "in_progress");
  assert.equal("conclusion" in pending, false);
  assert.equal(pending.head_sha, base.headCommitSha);
  const inconclusive = prepareGitHubCheckV1({ ...base, state: "inconclusive" });
  assert.equal(inconclusive.conclusion, "neutral");
  assert.match(inconclusive.output.summary, /does not establish a fix/);
  assert.equal("merged" in inconclusive, false);
});

test("verified status needs authentic accepted signed evidence and an exact commit", () => {
  for (const changes of [
    { reportDigest: null },
    { trustedQuorum: false },
    { artifactIntegrity: false },
    { independentlyQualified: false },
  ]) {
    assert.throws(() =>
      prepareGitHubCheckV1({
        ...base,
        state: "verified",
        reportDigest: "0x" + "b".repeat(64),
        independentlyQualified: true,
        trustedQuorum: true,
        artifactIntegrity: true,
        ...changes,
      }),
    );
  }
  const verified = prepareGitHubCheckV1({
    ...base,
    state: "verified",
    reportDigest: "0x" + "b".repeat(64),
    independentlyQualified: true,
    trustedQuorum: true,
    artifactIntegrity: true,
  });
  assert.equal(verified.status, "completed");
  assert.equal(verified.conclusion, "success");
  assert.match(verified.output.summary, /payment is authorized by this Check Run/i);
  assert.ok(!JSON.stringify(verified).includes("merge_method"));
});

test("disputed results demand action and cannot silently transform into success", () => {
  const disputed = prepareGitHubCheckV1({ ...base, state: "disputed" });
  assert.equal(disputed.conclusion, "action_required");
  assert.match(disputed.output.summary, /arbitration/);
  assert.throws(() =>
    prepareGitHubCheckV1({ ...base, headCommitSha: "untrusted" }),
  );
  assert.throws(() =>
    prepareGitHubCheckV1({ ...base, repositoryFullName: "../private" }),
  );
});
