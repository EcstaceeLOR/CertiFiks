#!/usr/bin/env node
/**
 * Independent, offline evidence integrity CLI.
 * Usage:
 *   node --import tsx scripts/verify-evidence.mjs bundle.json trusted-roster.json private-artifacts/
 *
 * trusted-roster.json MUST be provisioned separately from the downloaded
 * bundle, not taken from the report creator or bundled as a self-asserted key.
 */
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { verifyEvidenceBundleV1 } from "../packages/shared/src/evidence-report.ts";

const args = process.argv.slice(2);
if (args.length !== 3) {
  process.stderr.write(
    "Usage: node --import tsx scripts/verify-evidence.mjs bundle.json trusted-roster.json private-artifacts/\n",
  );
  process.exitCode = 2;
} else {
  try {
    const [reportPath, rosterPath, artifactDirectory] = args;
    const [reportBytes, rosterBytes, baseline, candidate, regressions] =
      await Promise.all([
        readFile(reportPath),
        readFile(rosterPath),
        readFile(join(artifactDirectory, "baseline-log.bin")),
        readFile(join(artifactDirectory, "candidate-log.bin")),
        readFile(join(artifactDirectory, "regression-log.bin")),
      ]);
    if (reportBytes.byteLength > 1024 * 1024 || rosterBytes.byteLength > 1024 * 1024) {
      throw new Error("Bundle or trusted roster exceeds size limit");
    }
    const bundle = JSON.parse(reportBytes.toString("utf8"));
    const roster = JSON.parse(rosterBytes.toString("utf8"));
    const result = verifyEvidenceBundleV1(bundle, roster, {
      "baseline-log": baseline,
      "candidate-log": candidate,
      "regression-log": regressions,
    });
    process.stdout.write(JSON.stringify({
      reportDigest: bundle.reportDigest,
      ...result,
      note: "Cryptographic integrity only; does not establish real tests or payment eligibility",
    }) + "\n");
  } catch (error) {
    // Never print private log contents or raw repository material.
    process.stderr.write("EVIDENCE_REJECTED: " +
      (error instanceof Error ? error.message : "unknown error") + "\n");
    process.exitCode = 1;
  }
}
