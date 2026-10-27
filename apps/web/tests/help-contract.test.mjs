import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const help = readFileSync(
  new URL("../app/help/page.tsx", import.meta.url),
  "utf8",
);
const css = readFileSync(
  new URL("../app/help/help.module.css", import.meta.url),
  "utf8",
);
const homepage = readFileSync(
  new URL("../app/page.tsx", import.meta.url),
  "utf8",
);
const onboarding = readFileSync(
  new URL("../app/onboarding/page.tsx", import.meta.url),
  "utf8",
);

test("help is reachable and accessible with semantic topic navigation", () => {
  for (const page of [homepage, onboarding]) {
    assert.match(page, /href="\/help"/);
  }
  assert.match(help, /className="skip-link"/);
  assert.match(help, /id="main-content"/);
  assert.match(help, /aria-label="Help topics"/);
  for (const part of ['id="roles"', 'id="faq"', 'id="support"']) {
    assert.ok(help.includes(part), part);
  }
  assert.match(help, /<details key=/);
  assert.match(help, /<summary>/);
  assert.match(css, /@media \(max-width: 640px\)/);
});

test("help does not fabricate custody, audit, fees, retention promises, or SLA", () => {
  for (const required of [
    "No live escrow is available.",
    "No binding fees",
    "not an independent audit",
    "privacy/retention policy",
    "No staffed incident hotline",
    "Do not send funds",
    "third-party support",
  ]) {
    assert.ok(help.includes(required), required);
  }
  for (const forbidden of [
    "audited and secure",
    "guaranteed payout",
    "guaranteed response within",
    "connectWallet(",
    "sendTransaction(",
  ]) {
    assert.ok(!help.includes(forbidden), forbidden);
  }
});

test("security escalation uses an existing policy, never a public exploit report", () => {
  assert.match(help, /Do not disclose exploit details in public issues/);
  assert.match(help, /CertiFiks\/security\/policy/);
  assert.match(help, /private\\s+vulnerability reporting if enabled/);
  assert.match(help, /Do not include private repository content/);
});
