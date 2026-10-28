import assert from "node:assert/strict";
import test from "node:test";
import {
  digestRunnerExecutionEvidenceV1,
  type VerifierRunResult,
} from "../src/index.js";
import {
  digestRunOutcomeV1,
  type QualificationPolicyV1,
  qualifyCandidateV1,
  type RunnerExecutorV1,
} from "../src/qualification.js";

const baseline: VerifierRunResult = {
  status: "failed",
  exitCode: 1,
  stdout: "",
  stderr: "AssertionError: expected vulnerable baseline failure\n",
  durationMs: 5,
  evidenceSha256: "b".repeat(64),
};
const passed: VerifierRunResult = {
  status: "passed",
  exitCode: 0,
  stdout: "1 passed\n",
  stderr: "",
  durationMs: 5,
  evidenceSha256: "c".repeat(64),
};
const regression: VerifierRunResult = {
  status: "passed",
  exitCode: 0,
  stdout: "15 passed\n",
  stderr: "",
  durationMs: 5,
  evidenceSha256: "d".repeat(64),
};
const policy: QualificationPolicyV1 = {
  baseCommitSha: "a".repeat(40),
  headCommitSha: "b".repeat(40),
  manifestDigest: "0x" + "1".repeat(64),
  testPlanDigest: "0x" + "2".repeat(64),
  trustedTestDigestAtBase: "0x" + "2".repeat(64),
  trustedTestDigestAtHead: "0x" + "2".repeat(64),
  image: "ubuntu/test@sha256:" + "a".repeat(64),
  acceptanceCommand: ["pytest", "tests/test_bug.py::test_regression"],
  regressionsCommand: ["pytest", "tests/test_regressions.py"],
  expectedBaselineFailureDigest: digestRunOutcomeV1(baseline),
  baselineWorkspace: "/tmp/pinned-base",
  candidateWorkspace: "/tmp/pinned-head",
};
const source = <T>(value: T): T => structuredClone(value);
function scripted(runs: VerifierRunResult[]): {
  executor: RunnerExecutorV1;
  history: string[];
} {
  const history: string[] = [];
  return {
    history,
    executor: async (input) => {
      history.push(input.workspace + ":" + input.command.join(" "));
      const next = runs.shift();
      if (!next) throw new Error("unexpected extra run");
      return {
        ...next,
        evidenceSha256: digestRunnerExecutionEvidenceV1(input, next),
      };
    },
  };
}

test("two baseline failures, two candidate passes and two regression passes qualify only as unsigned claim", async () => {
  const { executor, history } = scripted([
    baseline,
    baseline,
    passed,
    passed,
    regression,
    regression,
  ]);
  const result = await qualifyCandidateV1(policy, executor);
  assert.equal(result.outcome, "qualified");
  assert.equal(result.steps.length, 6);
  assert.equal(result.signed, false);
  assert.equal(result.payoutAuthorized, false);
  assert.equal(history.length, 6);
  assert.ok(history.slice(0, 2).every((x) => x.includes("pinned-base")));
  assert.ok(history.slice(2).every((x) => x.includes("pinned-head")));
  assert.notEqual(result.steps[0].outputDigest, result.steps[2].outputDigest);
});

test("baseline that already passes is rejected without executing candidate", async () => {
  const { executor, history } = scripted([passed, passed]);
  const result = await qualifyCandidateV1(policy, executor);
  assert.equal(result.outcome, "rejected");
  assert.equal(result.reason, "BASELINE_DID_NOT_FAIL");
  assert.equal(history.length, 2);
});

test("baseline unexpected failure reason is rejected", async () => {
  const { executor } = scripted([
    { ...baseline, stderr: "different assertion" },
    { ...baseline, stderr: "different assertion" },
  ]);
  const result = await qualifyCandidateV1(policy, executor);
  assert.equal(result.reason, "WRONG_BASELINE_FAILURE_REASON");
});

test("changing protected tests rejects before executing any untrusted container", async () => {
  const fake = scripted([]);
  const result = await qualifyCandidateV1(
    {
      ...policy,
      trustedTestDigestAtHead: "0x" + "9".repeat(64),
    },
    fake.executor,
  );
  assert.equal(result.reason, "TRUSTED_TESTS_CHANGED_OR_REMOVED");
  assert.equal(fake.history.length, 0);
});

test("flaky baseline or candidate refuses automatic qualification", async () => {
  const a = await qualifyCandidateV1(
    policy,
    scripted([baseline, { ...baseline, stdout: "time dependent output" }])
      .executor,
  );
  assert.equal(a.outcome, "needs_review");
  const b = await qualifyCandidateV1(
    policy,
    scripted([baseline, baseline, passed, { ...passed, stdout: "2 passed" }])
      .executor,
  );
  assert.equal(b.outcome, "needs_review");
});

test("candidate acceptance and regression failures never count as a fix", async () => {
  const a = await qualifyCandidateV1(
    policy,
    scripted([baseline, baseline, baseline, baseline]).executor,
  );
  assert.equal(a.reason, "CANDIDATE_DID_NOT_FIX_DEFECT");
  const b = await qualifyCandidateV1(
    policy,
    scripted([baseline, baseline, passed, passed, baseline, baseline]).executor,
  );
  assert.equal(b.reason, "REGRESSION_SUITE_FAILED");
});

test("runner outage, thrown container errors or timeouts never claim success", async () => {
  const infra = await qualifyCandidateV1(
    policy,
    scripted([{ ...baseline, status: "runner_error", exitCode: null }])
      .executor,
  );
  assert.equal(infra.outcome, "infrastructure_error");
  const timed = await qualifyCandidateV1(
    policy,
    scripted([{ ...baseline, status: "timed_out", exitCode: null }]).executor,
  );
  assert.equal(timed.outcome, "inconclusive");
  const crashed = await qualifyCandidateV1(policy, async () => {
    throw new Error("secret internal workspace path");
  });
  assert.equal(crashed.outcome, "infrastructure_error");
  assert.ok(!JSON.stringify(crashed).includes("secret internal"));
});

test("forged runner evidence hashes cannot qualify a baseline failure or a green fix", async () => {
  const forged = await qualifyCandidateV1(policy, async () => ({
    ...baseline,
    evidenceSha256: "f".repeat(64),
  }));
  assert.equal(forged.outcome, "infrastructure_error");
  assert.equal(forged.reason, "SANDBOX_EXECUTION_UNAVAILABLE");
  assert.equal(forged.steps.length, 0);
  assert.equal(forged.payoutAuthorized, false);

  const fakeGreen = await qualifyCandidateV1(
    policy,
    scripted([
      baseline,
      baseline,
      {
        ...passed,
        stdout: "0 tests discovered\n",
        evidenceSha256: "f".repeat(64),
      },
    ]).executor,
  );
  // Zero discovered tests cannot count as a real pass even with exit code 0.
  assert.equal(fakeGreen.outcome, "inconclusive");
  assert.equal(fakeGreen.payoutAuthorized, false);
});

test("empty or skipped test suites cannot satisfy a candidate pass", async () => {
  for (const line of ["no tests ran", "0 tests passed", "2 skipped", "all tests skipped"]) {
    const result = await qualifyCandidateV1(
      policy,
      scripted([
        baseline,
        baseline,
        { ...passed, stdout: line + "\n" },
      ]).executor,
    );
    assert.equal(result.outcome, "inconclusive", line);
    assert.equal(result.payoutAuthorized, false);
  }
});

test("truncated acceptance or regression output is inconclusive, never qualified", async () => {
  const truncated = await qualifyCandidateV1(
    policy,
    scripted([
      {
        ...baseline,
        stderr: "real failure\n[output truncated]",
      },
    ]).executor,
  );
  assert.equal(truncated.outcome, "inconclusive");
  assert.equal(truncated.payoutAuthorized, false);
  assert.equal(truncated.steps.length, 1);
});

test("immutable commit, image, acceptance and regression policies are mandatory", async () => {
  const invalid = [
    { ...policy, headCommitSha: policy.baseCommitSha },
    { ...policy, image: "ubuntu/test:latest" },
    { ...policy, acceptanceCommand: [""] },
    { ...policy, regressionsCommand: [...policy.acceptanceCommand] },
    { ...policy, candidateWorkspace: policy.baselineWorkspace },
  ];
  for (const item of invalid) {
    await assert.rejects(
      qualifyCandidateV1(item, scripted([]).executor),
      /QUALIFICATION_INVALID/,
    );
  }
});
