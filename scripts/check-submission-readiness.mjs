#!/usr/bin/env node
/**
 * Evidence-only checklist for CertiFiks Hacker House submissions.
 *
 * This tool does not query DoraHacks, cannot independently authenticate an
 * external receipt, and never marks a project submitted by itself.
 * --require-checkin / --require-final exit nonzero if evidence is missing.
 */
import { readFileSync } from "node:fs";

export const CHECKIN_KEYS = Object.freeze([
  "public_repo",
  "readme",
  "commit_history",
  "architecture_diagram",
  "working_core_flow",
  "qualifying_testnet",
  "contract_address",
  "testnet_transaction",
  "checkin_submitted",
]);
export const FINAL_KEYS = Object.freeze([
  ...CHECKIN_KEYS,
  "final_working_build",
  "final_video",
  "pitch_deck",
  "final_submission_submitted",
]);
const ACCEPTED_STATES = new Set(["verified", "missing", "blocked", "not_applicable"]);
const LIVE_URL = /^https:\/\/[a-z0-9.-]+(?:\/[^\s]*)?$/i;
const DEMO_KEYS = Object.freeze(["initial_demo_video", "initial_demo_live"]);

export function validateEvidenceLedger(ledger) {
  if (!ledger || typeof ledger !== "object" || Array.isArray(ledger)) throw new Error("Ledger must be an object");
  if (ledger.schemaVersion !== 1 || ledger.project !== "CertiFiks") throw new Error("Unexpected ledger or project version");
  if (!ledger.statuses || typeof ledger.statuses !== "object") throw new Error("Missing evidence statuses");
  for (const [key, item] of Object.entries(ledger.statuses)) {
    if (!item || typeof item !== "object" || !ACCEPTED_STATES.has(item.state)) {
      throw new Error("Invalid readiness state for " + key);
    }
    if (typeof item.owner !== "string" || !/^#[0-9]+$/.test(item.owner)) throw new Error("Missing issue owner for " + key);
    if (typeof item.note !== "string" || item.note.trim().length < 8) throw new Error("Missing note for " + key);
    if (item.state === "verified") {
      if (typeof item.evidence !== "string" || !LIVE_URL.test(item.evidence)) {
        throw new Error("Verified item lacks https evidence URL: " + key);
      }
      if (/\b(example\.com|placeholder|todo|tbd|localhost)\b/i.test(item.evidence)) {
        throw new Error("Verified evidence is a placeholder: " + key);
      }
    }
  }
  for (const key of [...FINAL_KEYS, ...DEMO_KEYS]) {
    if (!(key in ledger.statuses)) throw new Error("Required evidence item not tracked: " + key);
  }
  for (const key of ["checkinDeadlineWat", "finalDeadlineWat"]) {
    const v = ledger[key];
    if (typeof v !== "string" || !/^2026-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+01:00$/.test(v) || Number.isNaN(Date.parse(v))) {
      throw new Error("Invalid WAT date string for " + key);
    }
  }
  if (Date.parse(ledger.finalDeadlineWat) <= Date.parse(ledger.checkinDeadlineWat)) {
    throw new Error("Final deadline must be after check-in deadline");
  }
  return ledger;
}

export function evaluateReadiness(ledger, kind) {
  validateEvidenceLedger(ledger);
  if (!["checkin", "final"].includes(kind)) throw new Error("Unsupported gate: " + kind);
  const keys = kind === "checkin" ? CHECKIN_KEYS : FINAL_KEYS;
  const blockers = keys.filter(key => ledger.statuses[key].state !== "verified");
  // At check-in an actual live demo OR a brief video is expected.
  // At final a public demo video is independently required above.
  if (!DEMO_KEYS.some(key => ledger.statuses[key].state === "verified")) {
    blockers.push("initial_demo_video OR initial_demo_live");
  }
  // Unknown nationality/payout criteria require organizer verification; do not
  // invent country restrictions nor claim eligibility was established.
  if (ledger.statuses.nigeria_entry_and_prize.state !== "verified") {
    blockers.push("nigeria_entry_and_prize");
  }
  return {kind, ready: blockers.length === 0, verified: keys.filter(key => ledger.statuses[key].state === "verified"), blockers};
}

export function loadLedger() {
  return JSON.parse(readFileSync(new URL("../docs/hackathon/SUBMISSION_EVIDENCE.json", import.meta.url), "utf8"));
}

const invokedDirectly = process.argv[1] && import.meta.url === new URL("file://" + process.argv[1]).href;
if (invokedDirectly) {
  try {
    const ledger = loadLedger();
    const kind = process.argv.includes("--require-final") ? "final" : "checkin";
    const outcome = evaluateReadiness(ledger, kind);
    console.log(JSON.stringify(outcome, null, 2));
    if ((process.argv.includes("--require-checkin") || process.argv.includes("--require-final")) && !outcome.ready) {
      console.error("Submission readiness blocked: missing genuine evidence. Do not fabricate proof.");
      process.exitCode = 1;
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
