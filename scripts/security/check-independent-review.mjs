#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { verifyIndependentSecurityReviewV1 } from "./independent-review-gate.mjs";

const [reportPath, signaturePath, reviewerKeyPath, commit, reviewerOrg] = process.argv.slice(2);
if (!reportPath || !signaturePath || !reviewerKeyPath || !commit || !reviewerOrg ||
    process.argv.length !== 7) {
  console.error("Usage: node scripts/security/check-independent-review.mjs report.canonical.json report.sig trusted-reviewer.pub.pem expected-40hex-commit approved-reviewer-org");
  console.error("The trusted key and approved organization MUST come from an independently controlled security registry.");
  process.exitCode = 2;
} else {
  try {
    const [bytes, signature, key] = await Promise.all([
      readFile(reportPath),
      readFile(signaturePath, "utf8"),
      readFile(reviewerKeyPath, "utf8"),
    ]);
    const summary = verifyIndependentSecurityReviewV1(
      bytes, signature.trim(), key, commit, reviewerOrg,
    );
    console.log(JSON.stringify(summary, null, 2));
    console.log("AUTHENTICATED REVIEW STATEMENT ONLY: production approval still requires independent evidence validation.");
  } catch (error) {
    console.error(error instanceof Error ? error.message : "Security review could not be verified");
    process.exitCode = 1;
  }
}
