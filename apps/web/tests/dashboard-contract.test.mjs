import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

function read(path) {
  return readFileSync(new URL(path, import.meta.url), "utf8");
}
const dashboard = read("../app/dashboard/page.tsx");
const history = read("../app/dashboard/history.ts");
const detail = read("../app/dashboard/bounties/[bountyId]/page.tsx");
const exportRoute = read("../app/dashboard/export/route.ts");

test("public history is a real server-driven search, not a decorative dashboard", () => {
  assert.match(dashboard, /parseHistoryFilters\(await searchParams\)/);
  assert.match(dashboard, /await loadPublicHistory\(filters\)/);
  assert.match(dashboard, /method="get"/);
  assert.match(dashboard, /name="repo"/);
  assert.match(dashboard, /name="state"/);
  assert.match(dashboard, /name="sort"/);
  assert.match(dashboard, /historyQuery\(filters/);
  assert.match(dashboard, /Public records are unavailable/);
  assert.match(dashboard, /No matching published records/);
  assert.match(dashboard, /This is not a[\s\S]*count of all bounties/);
  assert.doesNotMatch(dashboard, /sampleVolume|mockBalance|fakePayouts/);
});

test("public bounties fail closed on malformed search and cannot expose tenant data", () => {
  assert.match(history, /\.every\(checkPublicHistoryItem\)/);
  assert.match(history, /item\.verificationProven/);
  assert.match(history, /cache: "no-store"/);
  assert.match(history, /redirect: "error"/);
  assert.match(history, /limit: "20"/);
  assert.match(history, /PUBLIC_STATES\.includes/);
  assert.match(history, /PUBLIC_SORTS\.includes/);
  assert.match(history, /\.protocol !== "https:"/);
  assert.doesNotMatch(history, /SUPABASE_SERVICE_ROLE_KEY|localStorage|sessionStorage/);
});

test("detail and export remain public, bounded, private-data-free and shareable", () => {
  assert.match(detail, /\/v1\/bounties\/\$\{bountyId\}/);
  assert.match(detail, /checkPublicHistoryItem\(item\)/);
  assert.match(detail, /not prove a completed fix/);
  assert.match(exportRoute, /parseHistoryFilters\(params\)/);
  assert.match(exportRoute, /text\/csv/);
  assert.match(exportRoute, /128 \* 1024/);
  assert.match(exportRoute, /Cache-Control/);
  assert.doesNotMatch(exportRoute, /SUPABASE_SERVICE_ROLE_KEY/);
});
