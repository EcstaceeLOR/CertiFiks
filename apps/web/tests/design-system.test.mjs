import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const app = join(dirname(fileURLToPath(import.meta.url)), "..", "app");
const read = (name) => readFileSync(join(app, name), "utf8");

test("both site journeys have keyboard skip links, landmarks and disabled-live disclosures", () => {
  const home = read("page.tsx");
  const onboard = read("onboarding/page.tsx");
  for (const file of [home, onboard]) {
    assert.match(file, /href="#main-content"/);
    assert.match(file, /id="main-content"/);
    assert.match(file, /aria-label="Primary navigation"/);
    assert.match(file, /<main/);
    assert.match(file, /<footer/);
    assert.match(file, /No live|not available|unavailable/i);
  }
  assert.match(home, /CONCEPT ONLY/);
  assert.match(home, /No live deposits/);
  assert.match(onboard, /No wallet connection or GitHub installation is performed here/);
  for (const role of ["sponsor", "contributor", "reviewer"]) {
    assert.match(onboard, new RegExp('id: "' + role + '"'));
  }
});

test("marketplace is tied to a real HTTP backend and never fabricates a bounty", () => {
  const src = read("page.tsx");
  assert.match(src, /process\.env\.CERTIFIKS_API_BASE_URL/);
  assert.match(src, /cache: "no-store"/);
  assert.match(src, /redirect: "error"/);
  assert.match(src, /AbortSignal\.timeout/);
  assert.match(src, /if \(!configured\) return \{ kind: "unavailable" \}/);
  assert.match(src, /listings\.kind === "unavailable"/);
  assert.match(src, /listings\.items\.length === 0/);
  assert.match(src, /verificationProven === false/);
  assert.match(src, /Fix verification has not been established/);
  assert.doesNotMatch(src, /mockBounties|sampleRewards|fakePayout|demoListings/);
});

test("WCAG-oriented focus, reduced-motion, reflow and explicit light/dark tokens exist", () => {
  const css = read("globals.css");
  assert.match(css, /a:focus-visible/);
  assert.match(css, /--focus:/);
  assert.match(css, /\.skip-link:focus/);
  assert.match(css, /prefers-reduced-motion: reduce/);
  assert.match(css, /prefers-color-scheme: light/);
  assert.match(css, /max-width: 640px/);
  assert.match(css, /--ink:/);
  assert.match(css, /--surface:/);
  assert.match(css, /--accent:/);
  assert.doesNotMatch(css, /outline:\s*none/);
});
