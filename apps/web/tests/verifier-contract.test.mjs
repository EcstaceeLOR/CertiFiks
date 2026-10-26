import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const route = join(dirname(fileURLToPath(import.meta.url)), "../app/verifier");

test("reviewer route has a protected, truthful initial state without sign buttons", () => {
  const page = readFileSync(join(route, "page.tsx"), "utf8");
  assert.match(page, /Live reviewer sessions are not enabled/);
  assert.match(page, /Review disabled/);
  assert.match(page, /No attestation or payout is performed here/);
  assert.match(page, /Nothing is signed automatically/);
  assert.match(page, /aria-label="Verifier navigation"/);
  assert.match(page, /href="#review-requirements"/);
  assert.match(page, /id="review-requirements"/);
  assert.doesNotMatch(page, /onClick\s*=|signMessage\(|writeContract\(|submitAttestation\(/);
});

test("reviewer focus, contrast and mobile reflow requirements have dedicated styling", () => {
  const css = readFileSync(join(route, "verifier.module.css"), "utf8");
  assert.match(css, /:focus-visible/);
  assert.match(css, /max-width: 760px/);
  assert.match(css, /prefers-reduced-motion: reduce/);
  assert.match(css, /prefers-color-scheme: light/);
});
