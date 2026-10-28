import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  digestAttemptV1,
  digestManifestV1,
  parseCanonicalManifestV1,
} from "../src/commitments.js";
import {
  isProtocolDocument,
  SchemaValidationError,
  validateProtocolDocument,
} from "../src/validation.js";

function json(rel: string): any {
  return JSON.parse(
    readFileSync(new URL("../../../protocol/" + rel, import.meta.url), "utf8"),
  );
}
const fixtures = [
  ["manifest", "bounty-manifest"],
  ["attempt", "candidate-attempt"],
  ["report", "verification-report"],
  ["vote", "signed-verifier-vote"],
  ["dispute", "dispute-case"],
  ["event", "chain-event"],
] as const;

for (const [kind, name] of fixtures) {
  test("schema accepts valid " + kind + " v1 fixture", () => {
    const value = json("examples/v1/" + name + ".json");
    assert.equal(isProtocolDocument(kind, value), true);
    validateProtocolDocument(kind, value);
  });
  test(
    "schema rejects wrong version and unrecognized fields for " + kind,
    () => {
      const value = json("examples/v1/" + name + ".json");
      assert.throws(
        () => validateProtocolDocument(kind, { ...value, version: "2" }),
        SchemaValidationError,
      );
      assert.throws(
        () => validateProtocolDocument(kind, { ...value, injected: true }),
        SchemaValidationError,
      );
    },
  );
}
test("manifest rejects missing baseline and poor sha provenance", () => {
  const input = json("examples/v1/bounty-manifest.json");
  delete input.acceptance.expectedFailureFingerprint;
  assert.throws(
    () => validateProtocolDocument("manifest", input),
    SchemaValidationError,
  );
  input.acceptance.expectedFailureFingerprint = "0x" + "A".repeat(64);
  assert.throws(
    () => validateProtocolDocument("manifest", input),
    SchemaValidationError,
  );
});
test("approval cannot claim candidate failed or regression suite failed", () => {
  const original = json("examples/v1/verification-report.json");
  assert.throws(
    () =>
      validateProtocolDocument("report", {
        ...original,
        candidate: { ...original.candidate, status: "failed" },
      }),
    SchemaValidationError,
  );
  assert.throws(
    () =>
      validateProtocolDocument("report", {
        ...original,
        regressionsPassed: false,
      }),
    SchemaValidationError,
  );
});
test("attestation commitment matches published cross-language vector", () => {
  const fixture = json("vectors/attestation-v1.json");
  assert.equal(digestAttemptV1(fixture.input), fixture.expected);
});
test("attestation domain binds changed chain, commit and expiry", () => {
  const { input } = json("vectors/attestation-v1.json");
  const base = digestAttemptV1(input);
  for (const changed of [
    { ...input, chainGenesis: "0x" + "12".repeat(32) },
    { ...input, headCommitSha: "c".repeat(40) },
    { ...input, bountyId: "18" },
    { ...input, expiryUnix: "1790000001" },
  ])
    assert.notEqual(digestAttemptV1(changed), base);
  assert.throws(() => digestAttemptV1({ ...input, repositoryId: "0001" }));
  assert.throws(() =>
    digestAttemptV1({ ...input, attemptId: "18446744073709551616" }),
  );
});
test("canonical RFC8785 manifest hash matches published cross-language fixture", () => {
  const fixture = json("vectors/manifest-v1.json");
  validateProtocolDocument("manifest", fixture.input);
  assert.equal(digestManifestV1(fixture.input), fixture.expected);
  const changed = {
    ...fixture.input,
    reward: { ...fixture.input.reward, amountAtoms: "100000000000001" },
  };
  assert.notEqual(digestManifestV1(changed), fixture.expected);
});
test("Unicode and control escapes match the cross-language UTF-16 golden vector", () => {
  // Canonical JSON key ordering follows JavaScript UTF-16 units, not Python
  // Unicode scalar-value ordering. This vector exercises both paths.
  const fixture = json("vectors/manifest-unicode-v1.json");
  assert.equal(digestManifestV1(fixture.input), fixture.expected);
  const changed = structuredClone(fixture.input);
  changed.strings["😀"] = "forged proof";
  assert.notEqual(digestManifestV1(changed), fixture.expected);
});

test("funded GitHub signature, fork and base-branch rules must be explicit", () => {
  const manifest = json("examples/v1/bounty-manifest.json");
  validateProtocolDocument("manifest", manifest);
  const missing = structuredClone(manifest);
  delete missing.acceptance.githubPolicy;
  assert.throws(
    () => validateProtocolDocument("manifest", missing),
    SchemaValidationError,
  );
  for (const changed of [
    { ...manifest.acceptance.githubPolicy, allowForkPullRequests: "yes" },
    {
      ...manifest.acceptance.githubPolicy,
      requireVerifiedCommitSignature: null,
    },
    { ...manifest.acceptance.githubPolicy, baseBranch: "" },
  ]) {
    const invalid = structuredClone(manifest);
    invalid.acceptance.githubPolicy = changed;
    assert.throws(
      () => validateProtocolDocument("manifest", invalid),
      SchemaValidationError,
    );
  }
  const retargeted = structuredClone(manifest);
  retargeted.acceptance.githubPolicy.baseBranch = "develop";
  validateProtocolDocument("manifest", retargeted);
  assert.notEqual(digestManifestV1(retargeted), digestManifestV1(manifest));
});

test("candidate v1 requires exact PR number, image and off-chain evidence digests", () => {
  const fixture = json("examples/v1/candidate-attempt.json");
  validateProtocolDocument("attempt", fixture);
  for (const field of ["pullNumber", "imageDigest", "evidenceDigest"]) {
    const changed = structuredClone(fixture);
    delete changed[field];
    assert.throws(
      () => validateProtocolDocument("attempt", changed),
      SchemaValidationError,
    );
  }
  const moved = { ...fixture, pullNumber: "0" };
  assert.throws(
    () => validateProtocolDocument("attempt", moved),
    SchemaValidationError,
  );
});

test("only canonical raw manifest JSON text is accepted for signed replay", () => {
  const fixture = json("vectors/manifest-v1.json");
  // Fixture contains only I-JSON strings, integers and arrays, making JS/Python JCS identical.
  const sortKeys = (v: any): any =>
    Array.isArray(v)
      ? v.map(sortKeys)
      : v && typeof v === "object"
        ? Object.fromEntries(
            Object.keys(v)
              .sort()
              .map((k) => [k, sortKeys(v[k])]),
          )
        : v;
  const canonical = JSON.stringify(sortKeys(fixture.input));
  assert.deepEqual(parseCanonicalManifestV1(canonical), fixture.input);
  assert.throws(() =>
    parseCanonicalManifestV1(JSON.stringify(fixture.input, null, 2)),
  );
  assert.throws(() =>
    parseCanonicalManifestV1('{"version":"1","version":"2"}'),
  );
});

test("EIP712 reviewer votes reject forged approvals and incomplete signatures", () => {
  const receipt = json("examples/v1/signed-verifier-vote.json");
  validateProtocolDocument("vote", receipt);
  for (const change of [
    { ...receipt, outcome: 1, baselineFailed: false },
    { ...receipt, outcome: 1, candidatePassed: false },
    { ...receipt, outcome: 1, regressionsPassed: false },
    { ...receipt, signature: "0x" + "aa".repeat(64) },
    { ...receipt, signerEpoch: "0" },
    { ...receipt, organizationId: "0x" + "ee".repeat(31) },
    { ...receipt, expiresAt: "0" },
    { ...receipt, chainId: "0" },
    { ...receipt, signatureScheme: "ed25519" },
  ]) {
    assert.throws(
      () => validateProtocolDocument("vote", change),
      SchemaValidationError,
    );
  }
  for (const negative of [2, 3, 4]) {
    validateProtocolDocument("vote", {
      ...receipt,
      outcome: negative,
      candidatePassed: false,
      regressionsPassed: false,
    });
  }
});

test("unsigned EIP712 signing intent is distinct from a verifiable signed report", () => {
  const complete = json("examples/v1/signed-verifier-vote.json");
  const { signature: _signature, ...unsigned } = complete;
  validateProtocolDocument("voteUnsigned", unsigned);
  assert.throws(
    () => validateProtocolDocument("vote", unsigned),
    SchemaValidationError,
  );
  assert.throws(
    () => validateProtocolDocument("voteUnsigned", complete),
    SchemaValidationError,
  );
});
