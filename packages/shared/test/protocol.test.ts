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
