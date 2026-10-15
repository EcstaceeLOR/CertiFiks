import { createHash } from "node:crypto";
import canonicalize from "canonicalize";

/**
 * Protocol v1 fixed-width attestation commitment.
 * This does not verify a signature, test result or chain state by itself.
 * Cryptographic signing and verified chain binding are implemented by #13/#18.
 */
export const PROTOCOL_VERSION = "1" as const;
export const ATTESTATION_DOMAIN = "CertiFiks:attempt-attestation:v1\0";
export const MANIFEST_DOMAIN = "CertiFiks:manifest:v1\0";
const HEX32 = /^0x[a-f0-9]{64}$/;
const SHA1 = /^[a-f0-9]{40}$/;
const DECIMAL = /^(0|[1-9][0-9]*)$/;
const MAX_U64 = (1n << 64n) - 1n;
const MAX_U256 = (1n << 256n) - 1n;

export interface AttemptCommitmentV1 {
  chainGenesis: string;
  contractLocatorHash: string;
  bountyId: string;
  attemptId: string;
  repositoryId: string;
  baseCommitSha: string;
  headCommitSha: string;
  manifestDigest: string;
  imageDigest: string;
  resultDigest: string;
  expiryUnix: string;
}

function fixedHex(value: string, bytes: 20 | 32, label: string): Buffer {
  if (
    typeof value !== "string" ||
    !(bytes === 20 ? SHA1.test(value) : HEX32.test(value))
  ) {
    throw new TypeError(
      "Invalid " +
        label +
        ": expected canonical lowercase hex of " +
        bytes +
        " bytes",
    );
  }
  return Buffer.from(bytes === 20 ? value : value.slice(2), "hex");
}

function uintBytes(value: string, byteLength: 8 | 32, label: string): Buffer {
  if (typeof value !== "string" || !DECIMAL.test(value)) {
    throw new TypeError(
      "Invalid " + label + ": expected a canonical decimal integer string",
    );
  }
  const integer = BigInt(value);
  if (integer > (byteLength === 8 ? MAX_U64 : MAX_U256)) {
    throw new RangeError(label + " exceeds uint" + byteLength * 8);
  }
  if (integer === 0n && (label === "bountyId" || label === "repositoryId")) {
    throw new RangeError(label + " must be nonzero");
  }
  const hex = integer.toString(16).padStart(byteLength * 2, "0");
  return Buffer.from(hex, "hex");
}

function sha256(data: Uint8Array): string {
  return "0x" + createHash("sha256").update(data).digest("hex");
}

/** RFC8785 canonical JSON manifest commitment with fixed domain separation. */
export function digestManifestV1(document: unknown): string {
  if (
    document === null ||
    Array.isArray(document) ||
    typeof document !== "object"
  ) {
    throw new TypeError("Manifest must be an object");
  }
  const canonical = canonicalize(document);
  if (typeof canonical !== "string" || canonical.length === 0) {
    throw new TypeError("Manifest is not canonicalizable JSON");
  }
  return sha256(
    Buffer.concat([
      Buffer.from(MANIFEST_DOMAIN, "utf8"),
      Buffer.from(canonical, "utf8"),
    ]),
  );
}

/**
 * Accept only raw *canonical* bytes for signature verification; this prevents
 * duplicate-key and serializer ambiguity, not merely JSON.parse agreement.
 */
export function parseCanonicalManifestV1(rawJson: string): unknown {
  if (typeof rawJson !== "string")
    throw new TypeError("Expected UTF-8 JSON text");
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawJson);
  } catch {
    throw new TypeError("Invalid JSON");
  }
  const canonical = canonicalize(parsed);
  if (canonical !== rawJson)
    throw new TypeError("Manifest bytes are not canonical RFC8785 JSON");
  return parsed;
}

/**
 * SHA256( ASCII domain incl NUL || genesis[32] || contractLocatorHash[32] ||
 * bountyId[32] || attemptId[8] || repositoryId[32] || baseSHA[20] ||
 * headSHA[20] || manifestDigest[32] || imageDigest[32] ||
 * resultDigest[32] || expiryUnix[8] ).
 *
 * Solidity abi.encodePacked must use matching bytes32, uint256, uint64 and bytes20.
 */
export function digestAttemptV1(input: AttemptCommitmentV1): string {
  const parts: Buffer[] = [
    Buffer.from(ATTESTATION_DOMAIN, "utf8"),
    fixedHex(input.chainGenesis, 32, "chainGenesis"),
    fixedHex(input.contractLocatorHash, 32, "contractLocatorHash"),
    uintBytes(input.bountyId, 32, "bountyId"),
    uintBytes(input.attemptId, 8, "attemptId"),
    uintBytes(input.repositoryId, 32, "repositoryId"),
    fixedHex(input.baseCommitSha, 20, "baseCommitSha"),
    fixedHex(input.headCommitSha, 20, "headCommitSha"),
    fixedHex(input.manifestDigest, 32, "manifestDigest"),
    fixedHex(input.imageDigest, 32, "imageDigest"),
    fixedHex(input.resultDigest, 32, "resultDigest"),
    uintBytes(input.expiryUnix, 8, "expiryUnix"),
  ];
  return sha256(Buffer.concat(parts));
}
