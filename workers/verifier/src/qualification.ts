import { createHash } from "node:crypto";
import {
  digestRunnerExecutionEvidenceV1,
  runUntrustedCode,
  type VerifierRunRequest,
  type VerifierRunResult,
} from "./index.js";

const SHA1 = /^[a-f0-9]{40}$/;
const SHA256 = /^0x[a-f0-9]{64}$/;
const EMPTY_OR_SKIPPED_TESTS =
  /(?:^|\n)\s*(?:0 tests?\b|no tests? (?:ran|collected|found|discovered)\b|all tests? skipped\b|\d+ skipped\b)/i;

export interface QualificationPolicyV1 {
  baseCommitSha: string;
  headCommitSha: string;
  manifestDigest: string;
  testPlanDigest: string;
  trustedTestDigestAtBase: string;
  trustedTestDigestAtHead: string;
  image: string;
  acceptanceCommand: string[];
  regressionsCommand: string[];
  expectedBaselineFailureDigest: string;
  baselineWorkspace: string;
  candidateWorkspace: string;
}

export type QualificationOutcomeV1 =
  | "qualified"
  | "rejected"
  | "needs_review"
  | "inconclusive"
  | "infrastructure_error";

export interface QualificationStepReceiptV1 {
  kind:
    | "baseline-acceptance"
    | "candidate-acceptance"
    | "candidate-regressions";
  repetition: 1 | 2;
  commitSha: string;
  image: string;
  command: string[];
  status: VerifierRunResult["status"];
  exitCode: number | null;
  outputDigest: string;
  runnerEvidenceSha256: string;
}

export interface QualificationReceiptV1 {
  protocolVersion: "1";
  outcome: QualificationOutcomeV1;
  reason: string;
  baseCommitSha: string;
  headCommitSha: string;
  manifestDigest: string;
  testPlanDigest: string;
  image: string;
  steps: QualificationStepReceiptV1[];
  signed: false;
  payoutAuthorized: false;
}

export type RunnerExecutorV1 = (
  request: VerifierRunRequest,
) => Promise<VerifierRunResult>;

export function digestRunOutcomeV1(
  value: Pick<VerifierRunResult, "status" | "exitCode" | "stdout" | "stderr">,
): string {
  return (
    "0x" +
    createHash("sha256")
      .update(
        JSON.stringify({
          status: value.status,
          exitCode: value.exitCode,
          stdout: value.stdout,
          stderr: value.stderr,
        }),
      )
      .digest("hex")
  );
}

function validate(input: QualificationPolicyV1): void {
  if (
    !SHA1.test(input.baseCommitSha) ||
    !SHA1.test(input.headCommitSha) ||
    input.baseCommitSha === input.headCommitSha
  ) {
    throw new Error("QUALIFICATION_INVALID: commit identity");
  }
  if (
    ![
      input.manifestDigest,
      input.testPlanDigest,
      input.trustedTestDigestAtBase,
      input.trustedTestDigestAtHead,
      input.expectedBaselineFailureDigest,
    ].every((x) => SHA256.test(x))
  ) {
    throw new Error("QUALIFICATION_INVALID: uncommitted evidence digest");
  }
  if (!/^[a-z0-9][a-z0-9./:_-]*@sha256:[a-f0-9]{64}$/i.test(input.image)) {
    throw new Error("QUALIFICATION_INVALID: unpinned runner image");
  }
  for (const command of [input.acceptanceCommand, input.regressionsCommand]) {
    if (
      !Array.isArray(command) ||
      command.length === 0 ||
      command.some(
        (x) => typeof x !== "string" || !x.trim() || x.includes("\0"),
      )
    ) {
      throw new Error("QUALIFICATION_INVALID: missing trusted test command");
    }
  }
  if (
    input.acceptanceCommand.join("\0") === input.regressionsCommand.join("\0")
  ) {
    throw new Error(
      "QUALIFICATION_INVALID: acceptance and regressions must be distinct",
    );
  }
  if (
    !input.baselineWorkspace ||
    !input.candidateWorkspace ||
    input.baselineWorkspace === input.candidateWorkspace
  ) {
    throw new Error(
      "QUALIFICATION_INVALID: same workspace for baseline and candidate",
    );
  }
}

function classify(
  value: VerifierRunResult,
): "success" | "failure" | "uncertain" | "error" {
  if (value.status === "runner_error") return "error";
  // An output buffer that exceeded the runner limit cannot be asserted as
  // proving the exact intended test failure or a complete passing suite.
  if (
    value.stdout.includes("[output truncated]") ||
    value.stderr.includes("[output truncated]")
  )
    return "uncertain";
  // A green exit with no executed tests or a skipped suite is not acceptance
  // evidence. These common framework markers are only a first defense:
  // trusted adapters must independently bind test identities/counts.
  const output = `${value.stdout}\n${value.stderr}`;
  if (EMPTY_OR_SKIPPED_TESTS.test(output)) return "uncertain";
  if (value.status === "passed" && value.exitCode === 0) return "success";
  if (
    value.status === "failed" &&
    typeof value.exitCode === "number" &&
    value.exitCode > 0
  )
    return "failure";
  return "uncertain";
}

/**
 * Only orchestrate server-fetched immutable checkout directories and the
 * funded, unmodified test commands. The executor defaults to the actual
 * network-disabled digest-pinned Docker runner.
 *
 * Never call this from a browser payload or release funds from its verdict.
 * A signed, enrolled, independent verifier result is a separate trust gate.
 */
export async function qualifyCandidateV1(
  policy: QualificationPolicyV1,
  executor: RunnerExecutorV1 = runUntrustedCode,
): Promise<QualificationReceiptV1> {
  validate(policy);
  const steps: QualificationStepReceiptV1[] = [];
  const result = (
    outcome: QualificationOutcomeV1,
    reason: string,
  ): QualificationReceiptV1 => ({
    protocolVersion: "1",
    outcome,
    reason,
    baseCommitSha: policy.baseCommitSha,
    headCommitSha: policy.headCommitSha,
    manifestDigest: policy.manifestDigest,
    testPlanDigest: policy.testPlanDigest,
    image: policy.image,
    steps,
    signed: false,
    payoutAuthorized: false,
  });

  if (
    policy.trustedTestDigestAtBase !== policy.testPlanDigest ||
    policy.trustedTestDigestAtHead !== policy.testPlanDigest
  ) {
    return result("rejected", "TRUSTED_TESTS_CHANGED_OR_REMOVED");
  }

  async function twice(
    kind: QualificationStepReceiptV1["kind"],
    workspace: string,
    commitSha: string,
    command: string[],
  ): Promise<VerifierRunResult[]> {
    const outcomes: VerifierRunResult[] = [];
    for (const repetition of [1, 2] as const) {
      const request: VerifierRunRequest = {
        workspace,
        image: policy.image,
        command: [...command],
        timeoutMs: 120000,
      };
      const value = await executor(request);
      if (
        !value ||
        !["passed", "failed", "runner_error", "timed_out"].includes(
          value.status,
        ) ||
        typeof value.stdout !== "string" ||
        typeof value.stderr !== "string" ||
        !Number.isSafeInteger(value.durationMs) ||
        value.durationMs < 0 ||
        !/^[a-f0-9]{64}$/.test(value.evidenceSha256) ||
        value.evidenceSha256 !== digestRunnerExecutionEvidenceV1(request, value)
      ) {
        throw new Error("invalid sandbox execution receipt");
      }
      steps.push({
        kind,
        repetition,
        commitSha,
        image: policy.image,
        command: [...command],
        status: value.status,
        exitCode: value.exitCode,
        outputDigest: digestRunOutcomeV1(value),
        runnerEvidenceSha256: value.evidenceSha256,
      });
      outcomes.push(value);
      if (classify(value) === "error" || classify(value) === "uncertain") break;
    }
    return outcomes;
  }

  try {
    const phases = [
      [
        "baseline-acceptance",
        policy.baselineWorkspace,
        policy.baseCommitSha,
        policy.acceptanceCommand,
      ],
      [
        "candidate-acceptance",
        policy.candidateWorkspace,
        policy.headCommitSha,
        policy.acceptanceCommand,
      ],
      [
        "candidate-regressions",
        policy.candidateWorkspace,
        policy.headCommitSha,
        policy.regressionsCommand,
      ],
    ] as const;
    for (const [kind, workspace, commitSha, command] of phases) {
      const runs = await twice(kind, workspace, commitSha, command);
      if (runs.some((v) => classify(v) === "error"))
        return result("infrastructure_error", "SANDBOX_UNAVAILABLE");
      if (runs.some((v) => classify(v) === "uncertain"))
        return result("inconclusive", "SANDBOX_TIMEOUT_OR_AMBIGUOUS_EXIT");
      if (
        runs.length !== 2 ||
        digestRunOutcomeV1(runs[0]) !== digestRunOutcomeV1(runs[1])
      )
        return result("needs_review", "FLAKY_OR_NONDETERMINISTIC_TEST");
      if (kind === "baseline-acceptance") {
        if (runs.some((v) => classify(v) !== "failure"))
          return result("rejected", "BASELINE_DID_NOT_FAIL");
        if (
          digestRunOutcomeV1(runs[0]) !== policy.expectedBaselineFailureDigest
        )
          return result("rejected", "WRONG_BASELINE_FAILURE_REASON");
      } else if (runs.some((v) => classify(v) !== "success")) {
        return result(
          "rejected",
          kind === "candidate-acceptance"
            ? "CANDIDATE_DID_NOT_FIX_DEFECT"
            : "REGRESSION_SUITE_FAILED",
        );
      }
    }
  } catch {
    // Do not leak runner stderr or private workspace paths to public callers.
    return result("infrastructure_error", "SANDBOX_EXECUTION_UNAVAILABLE");
  }
  return result("qualified", "SIX_REPRODUCIBLE_TEST_RUNS_RECORDED");
}
