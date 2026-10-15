import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
const page = readFileSync(new URL("../app/page.tsx", import.meta.url), "utf8");
test("landing route does not pretend escrow is deployed", () => {
  assert.match(page, /no live bounty marketplace/i);
  assert.match(page, /No funds can be deposited/i);
});
