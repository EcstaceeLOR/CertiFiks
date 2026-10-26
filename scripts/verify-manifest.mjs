#!/usr/bin/env node
/**
 * CertiFiks independent manifest commitment verification.
 * A manifest-provided digest cannot be trusted as the expected commitment.
 * Obtain --expected-digest from separately verified finalized chain state.
 *
 * node --import tsx scripts/verify-manifest.mjs canonical-manifest.json --expected-digest 0x...
 */
import { readFile } from "node:fs/promises";
import { TextDecoder } from "node:util";
import { admitCommittedManifestV1 } from "../packages/shared/src/manifest-admission.ts";

const argv = process.argv.slice(2);
if (
  argv.length !== 3 ||
  argv[1] !== "--expected-digest" ||
  !/^0x[a-f0-9]{64}$/.test(argv[2])
) {
  process.stderr.write(
    "Usage: node --import tsx scripts/verify-manifest.mjs canonical-manifest.json --expected-digest 0x<64-lowercase-hex>\n",
  );
  process.exitCode = 2;
} else {
  try {
    const content = await readFile(argv[0]);
    if (content.byteLength === 0 || content.byteLength > 1024 * 1024) {
      throw new Error("invalid manifest size");
    }
    const raw = new TextDecoder("utf-8", { fatal: true }).decode(content);
    const { digest } = admitCommittedManifestV1(raw, argv[2]);
    process.stdout.write(
      JSON.stringify({
        manifestDigest: digest,
        canonical: true,
        schemaValidated: true,
        matchedTrustedCommitment: true,
        fundingVerifiedByCli: false,
        note: "Digest equality does not prove funding, GitHub authorization, verification, or payout.",
      }) + "\n",
    );
  } catch {
    // Never echo repository-private manifest bytes or error data to stderr.
    process.stderr.write(
      "MANIFEST_REJECTED: canonical/schema/commitment mismatch or unreadable file\n",
    );
    process.exitCode = 1;
  }
}
