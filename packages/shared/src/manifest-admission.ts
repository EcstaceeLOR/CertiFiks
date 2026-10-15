import { timingSafeEqual } from "node:crypto";
import { digestManifestV1, parseCanonicalManifestV1 } from "./commitments.js";
import { validateProtocolDocument } from "./validation.js";

const SHA256_HEX = /^0x[a-f0-9]{64}$/;

/**
 * Verify raw canonical sponsor terms against a precommitted digest.
 *
 * This is a *document admission* check, not a signed approval, GitHub
 * provenance check, successful code-verification claim or on-chain receipt.
 * The caller must independently obtain the expected digest from trusted
 * finalized chain state; accepting a user-supplied expected digest defeats
 * the purpose of this function.
 */
export function admitCommittedManifestV1(
  rawCanonicalJson: string,
  expectedDigest: string,
): { document: unknown; digest: string } {
  if (!SHA256_HEX.test(expectedDigest)) {
    throw new TypeError("Expected a canonical lowercase SHA-256 commitment");
  }

  // Verify exact input bytes BEFORE parsing or accepting untrusted properties.
  const document = parseCanonicalManifestV1(rawCanonicalJson);
  validateProtocolDocument("manifest", document);

  const manifest = document as {
    acceptance: {
      githubPolicy: {
        baseBranch: string;
      };
    };
    review: {
      quorum: number;
      verifierOrganizations: string[];
    };
  };

  // JSON Schema bounds both fields, while this relation is cross-field.
  if (manifest.review.quorum > manifest.review.verifierOrganizations.length) {
    throw new TypeError("Reviewer quorum exceeds the committed roster");
  }

  const digest = digestManifestV1(document);
  const actualBytes = Buffer.from(digest.slice(2), "hex");
  const expectedBytes = Buffer.from(expectedDigest.slice(2), "hex");
  if (!timingSafeEqual(actualBytes, expectedBytes)) {
    throw new TypeError("Manifest does not match the funded commitment");
  }

  return { document, digest };
}
