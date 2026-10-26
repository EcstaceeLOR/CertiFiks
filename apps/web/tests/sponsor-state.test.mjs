import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const sponsor = readFileSync(new URL("../app/sponsor/page.tsx", import.meta.url), "utf8");
const onboarding = readFileSync(new URL("../app/onboarding/page.tsx", import.meta.url), "utf8");

test("sponsor view derives opportunities from real read-only backend, never local fixtures", () => {
  assert.match(sponsor, /process\.env\.CERTIFIKS_API_BASE_URL/);
  assert.match(sponsor, /\/v1\/bounties\?limit=12&offset=0/);
  assert.match(sponsor, /cache: "no-store"/);
  assert.match(sponsor, /redirect: "error"/);
  assert.match(sponsor, /role="status"/);
  assert.match(sponsor, /Public backend unavailable/);
  assert.match(sponsor, /No published bounties/);
  assert.match(sponsor, /verificationProven === false/);
});

test("no fake funding, signed wallet or private sponsor controls", () => {
  assert.match(sponsor, /Funding and private sponsor management are disabled/);
  assert.match(sponsor, /No verified custody deployment/);
  assert.match(sponsor, /Independent fix verification not proven/);
  assert.match(onboarding, /href="\/sponsor"/);
  assert.doesNotMatch(sponsor, /\.request\(\{ method: "eth_sendTransaction"/);
  assert.doesNotMatch(sponsor, /localStorage\.getItem/);
});

test("sponsor view has accessible landmarks, skip focus and role explanations", () => {
  assert.match(sponsor, /className="skip-link"/);
  assert.match(sponsor, /id="main-content"/);
  assert.match(sponsor, /aria-label="Primary navigation"/);
  assert.match(sponsor, /aria-labelledby="published-title"/);
  assert.match(sponsor, /Wallet transaction/);
  assert.match(sponsor, /Finality and audit trail/);
});
