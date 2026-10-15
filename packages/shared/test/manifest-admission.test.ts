import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import canonicalize from "canonicalize";
import { digestManifestV1 } from "../src/commitments.js";
import { admitCommittedManifestV1 } from "../src/manifest-admission.js";

interface Vector {
  input: Record<string, unknown>;
  expected: string;
}

interface TamperCase {
  path: string[];
  value: unknown;
}

function vector<T>(name: string): T {
  const url = new URL(`../../../protocol/vectors/${name}`, import.meta.url);
  return JSON.parse(readFileSync(url, "utf8")) as T;
}

function mutate(
  document: Record<string, unknown>,
  path: string[],
  value: unknown,
): Record<string, unknown> {
  const copy = structuredClone(document);
  let current = copy;
  for (const key of path.slice(0, -1)) {
    const next = current[key];
    if (next === null || typeof next !== "object" || Array.isArray(next)) {
      throw new TypeError("Invalid fixture mutation path");
    }
    current = next as Record<string, unknown>;
  }
  const last = path.at(-1);
  if (!last) throw new TypeError("Empty fixture path");
  current[last] = value;
  return copy;
}

const golden = vector<Vector>("manifest-v1.json");

test("admits only validated canonical bytes matching the funded commitment", () => {
  const canonical = canonicalize(golden.input);
  assert.ok(canonical);
  const admitted = admitCommittedManifestV1(canonical, golden.expected);
  assert.equal(admitted.digest, golden.expected);
  assert.deepEqual(admitted.document, golden.input);
  assert.throws(() =>
    admitCommittedManifestV1(
      JSON.stringify(golden.input, null, 2),
      golden.expected,
    ),
  );
  assert.throws(() =>
    admitCommittedManifestV1(canonical, golden.expected.toUpperCase()),
  );
});

test("all published terms changes invalidate the committed manifest", () => {
  const cases = vector<{ tampering: TamperCase[] }>("manifest-tamper-v1.json");
  for (const entry of cases.tampering) {
    const altered = mutate(golden.input, entry.path, entry.value);
    assert.notEqual(
      digestManifestV1(altered),
      golden.expected,
      entry.path.join("."),
    );
    const canonical = canonicalize(altered);
    assert.ok(canonical);
    assert.throws(
      () => admitCommittedManifestV1(canonical, golden.expected),
      entry.path.join("."),
    );
  }
});

test("rejects unsigned caller-controlled approvals and impossible quorum", () => {
  const altered = mutate(golden.input, ["review", "quorum"], 3);
  const canonical = canonicalize(altered);
  assert.ok(canonical);
  assert.throws(
    () => admitCommittedManifestV1(canonical, digestManifestV1(altered)),
    /quorum exceeds/,
  );
});
