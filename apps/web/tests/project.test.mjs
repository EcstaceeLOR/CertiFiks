import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const page = readFileSync(new URL("../app/page.tsx", import.meta.url), "utf8");
test("landing route does not pretend escrow is deployed", () => {
  assert.match(page, /Live listings are unavailable/i);
  assert.match(page, /No live deposits, funded rewards or automated payouts/i);
});
