import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const path = join(
  dirname(fileURLToPath(import.meta.url)),
  "../app/disputes/page.tsx",
);

test("dispute interface never shows a pretend payout, open case or signed verdict", () => {
  const src = readFileSync(path, "utf8");
  assert.match(src, /Live disputes and on-chain resolution are not enabled/);
  assert.match(src, /Dispute actions disabled/);
  assert.match(src, /There is no automatic verdict/);
  assert.match(src, /No authenticated case access/);
  assert.match(src, /aria-label="Dispute navigation"/);
  assert.match(src, /href="#dispute-workflow"/);
  assert.doesNotMatch(src, /onClick\s*=|writeContract\(|approveSettlement\(/);
});
