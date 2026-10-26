import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import {
  assembleEvidenceBundleV1,
  createEvidenceReportV1,
  signEvidenceReportV1,
  verifyEvidenceBundleV1,
  type EvidenceArtifactBytesV1,
  type EvidenceReportV1,
  type TrustedEvidenceSignerV1,
} from "../src/evidence-report.js";

const signerA = generateKeyPairSync("ed25519");
const signerB = generateKeyPairSync("ed25519");
const signerC = generateKeyPairSync("ed25519");
const pemPrivate = (pair: typeof signerA) =>
  pair.privateKey.export({ format: "pem", type: "pkcs8" }).toString();
const pemPublic = (pair: typeof signerA) =>
  pair.publicKey.export({ format: "pem", type: "spki" }).toString();

const roster: TrustedEvidenceSignerV1[] = [
  { keyId: "key-one", organizationId: "org-one", publicKeyPem: pemPublic(signerA) },
  { keyId: "key-two", organizationId: "org-two", publicKeyPem: pemPublic(signerB) },
];

const files: EvidenceArtifactBytesV1 = {
  "baseline-log": Buffer.from("baseline failed: assertion 27\n"),
  "candidate-log": Buffer.from("candidate passed: assertion 27\n"),
  "regression-log": Buffer.from("regression suite passed 15/15\n"),
};
const inputs: Omit<EvidenceReportV1, "version" | "artifacts"> = {
  repositoryId: "1234567",
  bountyId: "42",
  attemptId: "1",
  manifestDigest: "0x" + "11".repeat(32),
  imageDigest: "0x" + "22".repeat(32),
  baseCommitSha: "a".repeat(40),
  headCommitSha: "b".repeat(40),
  testPlanDigest: "0x" + "33".repeat(32),
  runnerResultDigest: "0x" + "44".repeat(32),
  createdAt: "2026-10-26T10:00:00.000Z",
  reportedDecision: "qualified",
};

function fixture() {
  const report = createEvidenceReportV1(inputs, files);
  const signatures = [
    signEvidenceReportV1(report, {
      keyId: "key-one", organizationId: "org-one", privateKeyPem: pemPrivate(signerA),
    }),
    signEvidenceReportV1(report, {
      keyId: "key-two", organizationId: "org-two", privateKeyPem: pemPrivate(signerB),
    }),
  ];
  return assembleEvidenceBundleV1(report, signatures);
}
const deep = <T>(value: T): T => structuredClone(value);

test("independently registered Ed25519 quorum proves exact private artifact bytes", () => {
  const bundle = fixture();
  const result = verifyEvidenceBundleV1(bundle, roster, files);
  assert.equal(result.integrity, "verified");
  assert.equal(result.reportedDecision, "qualified");
  assert.equal(result.payoutAuthorized, false);
  assert.match(bundle.reportDigest, /^0x[a-f0-9]{64}$/);
  for (const artifact of bundle.report.artifacts) {
    assert.equal(artifact.visibility, "private");
    assert.equal(Object.hasOwn(artifact, "data"), false);
  }
});

test("one-byte changes to report, signature and artifact always fail", () => {
  const original = fixture();
  const modified = deep(original);
  modified.report.headCommitSha = "c".repeat(40);
  assert.throws(() => verifyEvidenceBundleV1(modified, roster, files), /tampering/);
  const fakeDigest = deep(original);
  fakeDigest.reportDigest = "0x" + "aa".repeat(32);
  assert.throws(() => verifyEvidenceBundleV1(fakeDigest, roster, files), /tampering/);
  const altered = { ...files, "baseline-log": Buffer.from("baseline failed: assertion 28\n") };
  assert.throws(() => verifyEvidenceBundleV1(original, roster, altered), /tampering/);
  const fakeSignature = deep(original);
  fakeSignature.signatures[0].signatureBase64 = "A" + fakeSignature.signatures[0].signatureBase64.slice(1);
  assert.throws(() => verifyEvidenceBundleV1(fakeSignature, roster, files));
});

test("missing logs, untrusted keys, revoked identities and one-organization quorum fail closed", () => {
  const bundle = fixture();
  const absent = { ...files, "candidate-log": undefined } as unknown as EvidenceArtifactBytesV1;
  assert.throws(() => verifyEvidenceBundleV1(bundle, roster, absent), /missing private/);
  assert.throws(() => verifyEvidenceBundleV1(bundle, [roster[0]], files), /untrusted/);
  assert.throws(() => verifyEvidenceBundleV1(bundle, [
    { ...roster[0], revoked: true }, roster[1],
  ], files), /untrusted/);
  const duplicate = deep(bundle);
  duplicate.signatures[1].organizationId = "org-one";
  assert.throws(() => verifyEvidenceBundleV1(duplicate, roster, files), /duplicate/);
  assert.throws(() => verifyEvidenceBundleV1(
    assembleEvidenceBundleV1(bundle.report, bundle.signatures.slice(0, 1)),
    roster, files,
  ), /two enrolled/);
  assert.throws(() => signEvidenceReportV1(bundle.report, {
    keyId: "key-evil", organizationId: "org-evil", privateKeyPem:
      generateKeyPairSync("rsa", { modulusLength: 2048 })
        .privateKey.export({ format: "pem", type: "pkcs8" }).toString(),
  }), /Ed25519/);
});

test("manifest, image, test plan, commit and strict private-log descriptors cannot be altered", () => {
  for (const field of ["manifestDigest", "imageDigest", "testPlanDigest", "runnerResultDigest"] as const) {
    const tampered = deep(fixture());
    tampered.report[field] = "0x" + "ee".repeat(32);
    assert.throws(() => verifyEvidenceBundleV1(tampered, roster, files));
  }
  const publicLog = deep(fixture());
  publicLog.report.artifacts[0].visibility = "public" as "private";
  assert.throws(() => verifyEvidenceBundleV1(publicLog, roster, files), /publicly disclosed/);
  const extra = deep(fixture()) as unknown as Record<string, unknown>;
  extra.untrustedResult = true;
  assert.throws(() => verifyEvidenceBundleV1(extra as unknown as ReturnType<typeof fixture>, roster, files), /unexpected/);
});

test("external verification CLI reproduces signed bundle offline and rejects absent private artifact", async () => {
  const tmp = await mkdtemp(join(tmpdir(), "certifiks-evidence-"));
  const folder = join(tmp, "private");
  try {
    await mkdir(folder);
    await writeFile(join(tmp, "bundle.json"), JSON.stringify(fixture()));
    await writeFile(join(tmp, "trusted.json"), JSON.stringify(roster));
    for (const [role, bytes] of Object.entries(files)) {
      await writeFile(join(folder, role + ".bin"), bytes);
    }
    const cli = new URL("../../../scripts/verify-evidence.mjs", import.meta.url);
    const run = () => spawnSync(process.execPath, [
      "--import", "tsx", cli.pathname,
      join(tmp, "bundle.json"), join(tmp, "trusted.json"), folder,
    ], { encoding: "utf8", cwd: new URL("../../..", import.meta.url).pathname });
    let output = run();
    assert.equal(output.status, 0, output.stderr);
    assert.equal(JSON.parse(output.stdout).payoutAuthorized, false);
    await rm(join(folder, "regression-log.bin"));
    output = run();
    assert.equal(output.status, 1);
    assert.match(output.stderr, /EVIDENCE_REJECTED/);
  } finally {
    await rm(tmp, { recursive: true, force: true });
  }
});
