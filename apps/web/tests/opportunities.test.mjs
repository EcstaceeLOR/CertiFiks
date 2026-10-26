import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const opportunity = readFileSync(
  new URL("../app/opportunities/page.tsx", import.meta.url),
  "utf8",
);
const home = readFileSync(new URL("../app/page.tsx", import.meta.url), "utf8");
const onboarding = readFileSync(
  new URL("../app/onboarding/page.tsx", import.meta.url),
  "utf8",
);

test("contributor discovery is linked and does not pretend to apply, withdraw, or sign funds", () => {
  assert.match(home, /href="\/opportunities"/);
  assert.match(onboarding, /href="\/opportunities"/);
  assert.match(
    opportunity,
    /Contributor applications and earnings are not enabled/,
  );
  assert.match(opportunity, /APPLICATION UNAVAILABLE/);
  assert.match(opportunity, /wallet payouts must be operational/);
  assert.doesNotMatch(
    opportunity,
    /onClick=|POST.*\/applications|sendTransaction/,
  );
});

test("contributor browsing is live-data only and fails visibly without configured API", () => {
  assert.match(opportunity, /CERTIFIKS_API_BASE_URL/);
  assert.match(opportunity, /cache: "no-store"/);
  assert.match(opportunity, /verificationProven === false/);
  assert.match(opportunity, /result\.kind === "unavailable"/);
  assert.match(opportunity, /result\.kind === "invalid"/);
  assert.match(opportunity, /No matching published bounties/);
  assert.match(opportunity, /No simulated rewards or results/);
});

test("filterable pagination is bounded and exact before displaying public-only backend results", () => {
  assert.match(opportunity, /const PER_PAGE = 12/);
  assert.match(opportunity, /if \(page > 100\) return null/);
  assert.match(opportunity, /endpoint\.searchParams\.set\("state"/);
  assert.match(opportunity, /endpoint\.searchParams\.set\("repo"/);
  assert.match(opportunity, /endpoint\.searchParams\.set\("offset"/);
  assert.match(opportunity, /Filters apply at the live backend/);
});
