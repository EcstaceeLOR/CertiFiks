import { validateProtocolDocument } from "./validation.js";

/**
 * Type-safe, read-only construction of the Solidity v1 EIP-712 verifier vote.
 * This produces data to sign; it DOES NOT create a signature, authenticate
 * GitHub reports, or authorize a payout. The signature must be verified by
 * SignedVerifierDecisionModuleV1 against an enrolled organization.
 */
const UINT64_MAX = (1n << 64n) - 1n;
const UINT256_MAX = (1n << 256n) - 1n;

const fieldTypes = [
  { name: "bountyId", type: "uint256" },
  { name: "attemptId", type: "uint64" },
  { name: "organizationId", type: "bytes32" },
  { name: "signerEpoch", type: "uint64" },
  { name: "attemptDigest", type: "bytes32" },
  { name: "manifestDigest", type: "bytes32" },
  { name: "verifierPolicyDigest", type: "bytes32" },
  { name: "headGitSha", type: "bytes20" },
  { name: "reportDigest", type: "bytes32" },
  { name: "imageDigest", type: "bytes32" },
  { name: "outcome", type: "uint8" },
  { name: "baselineFailed", type: "bool" },
  { name: "candidatePassed", type: "bool" },
  { name: "regressionsPassed", type: "bool" },
  { name: "expiresAt", type: "uint64" },
] as const;

export const CERTIFIKS_VERIFIER_TYPED_FIELDS = fieldTypes;
export const CERTIFIKS_VERIFIER_TYPED_PRIMARY_TYPE = "CertiFiksVerifierVote" as const;

export interface VerifierVoteEnvelopeV1 {
  version: "1";
  chainId: string;
  verifyingContract: `0x${string}`;
  bountyId: string;
  attemptId: string;
  organizationId: `0x${string}`;
  signerEpoch: string;
  attemptDigest: `0x${string}`;
  manifestDigest: `0x${string}`;
  verifierPolicyDigest: `0x${string}`;
  headGitSha: `0x${string}`;
  reportDigest: `0x${string}`;
  imageDigest: `0x${string}`;
  outcome: 1 | 2 | 3 | 4;
  baselineFailed: boolean;
  candidatePassed: boolean;
  regressionsPassed: boolean;
  expiresAt: string;
  signatureScheme: "eip712-secp256k1";
  signature: `0x${string}`;
}

function parseUintString(field: string, input: string, max: bigint): bigint {
  if (!/^[1-9][0-9]*$/.test(input)) {
    throw new Error(field + " must be a canonical positive decimal integer");
  }
  const parsed = BigInt(input);
  if (parsed > max) {
    throw new RangeError(field + " exceeds EVM integer width");
  }
  return parsed;
}

export function prepareVerifierVoteTypedDataV1(source: unknown) {
  validateProtocolDocument("vote", source);
  const vote = source as VerifierVoteEnvelopeV1;

  return {
    domain: {
      name: "CertiFiksVerifier",
      version: "1",
      chainId: parseUintString("chainId", vote.chainId, UINT256_MAX),
      verifyingContract: vote.verifyingContract,
    },
    types: {
      CertiFiksVerifierVote: CERTIFIKS_VERIFIER_TYPED_FIELDS,
    },
    primaryType: CERTIFIKS_VERIFIER_TYPED_PRIMARY_TYPE,
    message: {
      bountyId: parseUintString("bountyId", vote.bountyId, UINT256_MAX),
      attemptId: parseUintString("attemptId", vote.attemptId, UINT64_MAX),
      organizationId: vote.organizationId,
      signerEpoch: parseUintString("signerEpoch", vote.signerEpoch, UINT64_MAX),
      attemptDigest: vote.attemptDigest,
      manifestDigest: vote.manifestDigest,
      verifierPolicyDigest: vote.verifierPolicyDigest,
      headGitSha: vote.headGitSha,
      reportDigest: vote.reportDigest,
      imageDigest: vote.imageDigest,
      outcome: vote.outcome,
      baselineFailed: vote.baselineFailed,
      candidatePassed: vote.candidatePassed,
      regressionsPassed: vote.regressionsPassed,
      expiresAt: parseUintString("expiresAt", vote.expiresAt, UINT64_MAX),
    },
  } as const;
}
