/**
 * Exact GitHub Checks request PREPARATION only; this module never calls GitHub.
 * The caller must be a separately authorized app installation and MUST fetch
 * final, policy-checked evidence from trusted immutable server storage.
 */
const SHA = /^[a-f0-9]{40}$/;
const DIGEST = /^0x[a-f0-9]{64}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const UINT = /^[1-9][0-9]*$/;

export interface TrustedQualificationV1 {
  repositoryFullName: string;
  repositoryId: string;
  attemptId: string;
  headCommitSha: string;
  state: "pending" | "inconclusive" | "verified" | "rejected" | "disputed";
  reportDigest: string | null;
  independentlyQualified: boolean;
  trustedQuorum: boolean;
  artifactIntegrity: boolean;
}

export interface PreparedGitHubCheckRunV1 {
  name: "CertiFiks independent verification";
  head_sha: string;
  external_id: string;
  status: "in_progress" | "completed";
  conclusion?: "neutral" | "success" | "failure" | "action_required";
  output: {
    title: string;
    summary: string;
  };
}

/**
 * This returns a payload, NOT approval to publish and NOT a real Check Run.
 * No auto-merge, funding or escrow effects occur.
 */
export function prepareGitHubCheckV1(
  v: TrustedQualificationV1,
): PreparedGitHubCheckRunV1 {
  if (
    !REPO.test(v.repositoryFullName) ||
    /(^|\/)\.{1,2}(\/|$)/.test(v.repositoryFullName) ||
    !UINT.test(v.repositoryId) ||
    !UINT.test(v.attemptId) ||
    !SHA.test(v.headCommitSha) ||
    !["pending", "inconclusive", "verified", "rejected", "disputed"].includes(
      v.state,
    ) ||
    ![v.independentlyQualified, v.trustedQuorum, v.artifactIntegrity].every(
      (item) => typeof item === "boolean",
    ) ||
    (v.reportDigest !== null && !DIGEST.test(v.reportDigest))
  )
    throw new TypeError(
      "GitHub Check: invalid or untrusted qualification binding",
    );

  const documentedOutcome =
    v.reportDigest !== null && v.trustedQuorum && v.artifactIntegrity;

  if (["verified", "rejected"].includes(v.state) && !documentedOutcome) {
    throw new TypeError(
      "GitHub Check: signed independent evidence is required for terminal claim",
    );
  }
  if (v.state === "verified" && !v.independentlyQualified) {
    throw new TypeError(
      "GitHub Check: cannot claim verified without independent qualification",
    );
  }
  if (v.state === "rejected" && v.independentlyQualified) {
    throw new TypeError(
      "GitHub Check: contradictory independent qualification",
    );
  }

  const common = {
    name: "CertiFiks independent verification" as const,
    head_sha: v.headCommitSha,
    external_id: `cfk:${v.repositoryId}:${v.attemptId}:${v.headCommitSha}`,
  };

  if (v.state === "pending") {
    return {
      ...common,
      status: "in_progress",
      output: {
        title: "Verification pending",
        summary:
          "Independent evidence has not yet been accepted. This is not an approval, merge or payout.",
      },
    };
  }
  const metadata = {
    inconclusive: {
      conclusion: "neutral",
      title: "Verification inconclusive",
      text: "The recorded evidence does not establish a fix.",
    },
    verified: {
      conclusion: "success",
      title: "Fix independently qualified",
      text: "Qualified under the persisted report and reviewer policy. Chain settlement remains separate.",
    },
    rejected: {
      conclusion: "failure",
      title: "Fix did not satisfy acceptance requirements",
      text: "Rejection is bound to an independently reviewed report, not an automated merge.",
    },
    disputed: {
      conclusion: "action_required",
      title: "Qualification disputed",
      text: "Human arbitration is required. No payout is implied.",
    },
  } as const;
  const info = metadata[v.state];
  return {
    ...common,
    status: "completed",
    conclusion: info.conclusion,
    output: {
      title: info.title,
      summary: `${info.text} ${v.reportDigest ? `Evidence digest: ${v.reportDigest}. ` : ""}Neither PR merge nor payment is authorized by this Check Run.`,
    },
  };
}
