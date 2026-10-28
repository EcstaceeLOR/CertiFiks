#!/usr/bin/env node
/**
 * Independent, offline evidence integrity CLI.
 * Usage:
 *   node --import tsx scripts/verify-evidence.mjs bundle.json trusted-roster.json private-artifacts/
 *
 * trusted-roster.json MUST be provisioned separately from the downloaded
 * bundle, not taken from the report creator or bundled as a self-asserted key.
 */
import { constants } from "node:fs";
import { open } from "node:fs/promises";
import { join } from "node:path";
import { verifyEvidenceBundleV1 } from "../packages/shared/src/evidence-report.ts";

const MAX_PRIVATE_BYTES = 1024 * 1024;

/**
 * Never read an unlimited caller-supplied file or follow symlinks to
 * unrelated host paths. Read at most the configured bound plus one byte,
 * and verify the opened inode rather than a pre-open pathname.
 */
async function readBoundedRegularFile(path) {
  if (typeof constants.O_NOFOLLOW !== "number") {
    throw new Error("evidence input platform lacks no-follow protection");
  }
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const info = await file.stat();
    if (!info.isFile() || info.size <= 0 || info.size > MAX_PRIVATE_BYTES) {
      throw new Error("evidence input is not a bounded regular file");
    }
    const bytes = Buffer.alloc(MAX_PRIVATE_BYTES + 1);
    let length = 0;
    while (length < bytes.length) {
      const { bytesRead } = await file.read(
        bytes,
        length,
        bytes.length - length,
        null,
      );
      if (bytesRead === 0) break;
      length += bytesRead;
    }
    if (length === 0 || length > MAX_PRIVATE_BYTES) {
      throw new Error("evidence input size invalid");
    }
    return bytes.subarray(0, length);
  } finally {
    await file.close();
  }
}

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
        readBoundedRegularFile(reportPath),
        readBoundedRegularFile(rosterPath),
        readBoundedRegularFile(join(artifactDirectory, "baseline-log.bin")),
        readBoundedRegularFile(join(artifactDirectory, "candidate-log.bin")),
        readBoundedRegularFile(join(artifactDirectory, "regression-log.bin")),
      ]);
    const bundle = JSON.parse(reportBytes.toString("utf8"));
    const roster = JSON.parse(rosterBytes.toString("utf8"));
    const result = verifyEvidenceBundleV1(bundle, roster, {
      "baseline-log": baseline,
      "candidate-log": candidate,
      "regression-log": regressions,
    });
    process.stdout.write(
      JSON.stringify({
        reportDigest: bundle.reportDigest,
        ...result,
        note: "Cryptographic integrity only; does not establish real tests or payment eligibility",
      }) + "\n",
    );
  } catch {
    // Neither internal file paths nor untrusted artifact contents can be
    // reflected into a CLI message, a support ticket or public CI logs.
    process.stderr.write("EVIDENCE_REJECTED\n");
    process.exitCode = 1;
  }
}
