import assert from "node:assert/strict";
import test from "node:test";
import {
  evaluateReadiness,
  loadLedger,
  validateEvidenceLedger,
} from "./check-submission-readiness.mjs";

const clone = (value) => JSON.parse(JSON.stringify(value));
const ledger = loadLedger();

test("actual tracker is valid but not presented as ready", () => {
  validateEvidenceLedger(ledger);
  const checkin = evaluateReadiness(ledger, "checkin");
  const final = evaluateReadiness(ledger, "final");
  assert.equal(checkin.ready, false);
  assert.equal(final.ready, false);
  assert.ok(checkin.blockers.includes("qualifying_testnet"));
  assert.ok(checkin.blockers.includes("working_core_flow"));
  assert.ok(
    checkin.blockers.includes("initial_demo_video OR initial_demo_live"),
  );
  assert.ok(final.blockers.includes("final_submission_submitted"));
});

test("verified item must contain non-placeholder HTTPS evidence URL", () => {
  const modified = clone(ledger);
  modified.statuses.qualifying_testnet.state = "verified";
  assert.throws(() => validateEvidenceLedger(modified), /lacks https evidence/);
  modified.statuses.qualifying_testnet.evidence =
    "https://example.com/fake-proof";
  assert.throws(() => validateEvidenceLedger(modified), /placeholder/);
  modified.statuses.qualifying_testnet.evidence = "http://github.com/public";
  assert.throws(() => validateEvidenceLedger(modified), /lacks https evidence/);
});

test("unknown evidence status, missing owner and invalid deadline fail fast", () => {
  const modified = clone(ledger);
  modified.statuses.contract_address.state = "done";
  assert.throws(() => validateEvidenceLedger(modified), /Invalid readiness/);
  modified.statuses.contract_address.state = "missing";
  modified.statuses.contract_address.owner = "";
  assert.throws(() => validateEvidenceLedger(modified), /Missing issue owner/);
  modified.statuses.contract_address.owner = "#18";
  modified.finalDeadlineWat = "2026-10-01T05:00:00+01:00";
  assert.throws(() => validateEvidenceLedger(modified), /after check-in/);
});

test("a draft demo page does not satisfy both gates", () => {
  const modified = clone(ledger);
  modified.statuses.initial_demo_live.state = "verified";
  modified.statuses.initial_demo_live.evidence =
    "https://github.com/EcstaceeLOR/CertiFiks";
  const result = evaluateReadiness(modified, "checkin");
  assert.equal(result.ready, false);
  assert.ok(result.blockers.includes("testnet_transaction"));
  assert.ok(result.blockers.includes("nigeria_entry_and_prize"));
});

test("gates require independent final-specific proof, not just check-in", () => {
  const synthetic = clone(ledger);
  for (const [key, item] of Object.entries(synthetic.statuses)) {
    if (["testnet_explorer", "organizer_v3_rpc"].includes(key)) continue;
    item.state = "verified";
    item.evidence = "https://github.com/EcstaceeLOR/CertiFiks/commits/main";
  }
  assert.equal(evaluateReadiness(synthetic, "checkin").ready, true);
  synthetic.statuses.final_video.state = "missing";
  assert.equal(evaluateReadiness(synthetic, "final").ready, false);
});
