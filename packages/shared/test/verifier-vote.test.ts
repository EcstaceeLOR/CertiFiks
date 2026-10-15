import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { prepareVerifierVoteTypedDataV1 } from "../src/verifier-vote.js";

const signedFixture = JSON.parse(
  readFileSync(
    new URL(
      "../../../protocol/examples/v1/signed-verifier-vote.json",
      import.meta.url,
    ),
    "utf8",
  ),
);

const { signature: _signature, ...fixture } = signedFixture;

test("unsigned vote prepares precise EIP712 chain, contract, full field ordering and typed outcome", () => {
  const data = prepareVerifierVoteTypedDataV1(fixture);
  assert.equal(data.domain.name, "CertiFiksVerifier");
  assert.equal(data.domain.version, "1");
  assert.equal(data.domain.chainId, 31337n);
  assert.equal(data.primaryType, "CertiFiksVerifierVote");
  assert.equal(data.message.attemptId, 1n);
  assert.equal(data.message.bountyId, 7n);
  assert.equal(data.message.outcome, 1);
  assert.deepEqual(
    data.types.CertiFiksVerifierVote.map((field) => field.name),
    [
      "bountyId",
      "attemptId",
      "organizationId",
      "signerEpoch",
      "attemptDigest",
      "manifestDigest",
      "verifierPolicyDigest",
      "headGitSha",
      "reportDigest",
      "imageDigest",
      "outcome",
      "baselineFailed",
      "candidatePassed",
      "regressionsPassed",
      "expiresAt",
    ],
  );
});

test("out-of-range attempt/epoch/deadline never silently round", () => {
  const UINT64_OVERFLOW = (1n << 64n).toString();
  for (const field of ["attemptId", "signerEpoch", "expiresAt"]) {
    assert.throws(
      () =>
        prepareVerifierVoteTypedDataV1({
          ...fixture,
          [field]: UINT64_OVERFLOW,
        }),
      RangeError,
    );
  }
  assert.throws(
    () =>
      prepareVerifierVoteTypedDataV1({
        ...fixture,
        bountyId: (1n << 256n).toString(),
      }),
    RangeError,
  );
});

test("canonical numeric identities never accept leading zeros, floats or empty values", () => {
  for (const invalid of ["01", "0", "-7", "1.5", "", " 7", "NaN"]) {
    assert.throws(() =>
      prepareVerifierVoteTypedDataV1({ ...fixture, bountyId: invalid }),
    );
  }
});

test("unverified or incomplete approval is never prepared for signing", () => {
  for (const field of [
    "baselineFailed",
    "candidatePassed",
    "regressionsPassed",
  ]) {
    assert.throws(() =>
      prepareVerifierVoteTypedDataV1({
        ...fixture,
        [field]: false,
      }),
    );
  }
  assert.equal(
    prepareVerifierVoteTypedDataV1({
      ...fixture,
      outcome: 4,
      baselineFailed: false,
      candidatePassed: false,
      regressionsPassed: false,
    }).message.outcome,
    4,
  );
});
