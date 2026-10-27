import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  calculateUnitEconomics,
  EconomicsInputError,
} from "./unit-economics.mjs";

const sample = JSON.parse(
  readFileSync(
    new URL("./unit-economics.example.json", import.meta.url),
    "utf8",
  ),
);

test("synthetic scenario computes exact costs, margin and break even", () => {
  const result = calculateUnitEconomics(sample);
  assert.equal(result.assumptionsAreMeasured, false);
  assert.equal(result.productionBillingEnabled, false);
  assert.equal(result.costPerCompletedBountyCentsUpperBound, "1255");
  assert.equal(result.directCostPerCompletedBountyCents, "1080");
  assert.equal(result.fixedMonthlyCents, "19000");
  assert.equal(result.monthlyExpectedVariableCostCents, "50200");
  assert.equal(result.monthlyRevenueCents, "72000");
  assert.equal(result.monthlyExpectedTotalCostCents, "69200");
  assert.equal(result.monthlyExpectedSurplusCents, "2800");
  assert.equal(result.breakEvenCompletedBountiesPerMonth, "35");
});

test("underpricing disables break-even instead of inventing profitability", () => {
  const data = structuredClone(sample);
  data.assumptions.sponsorFeeCentsPerCompletedBounty = 100;
  const result = calculateUnitEconomics(data);
  assert.equal(result.breakEvenCompletedBountiesPerMonth, null);
  assert.equal(result.profitablePerIncrement, false);
  assert.equal(BigInt(result.monthlyExpectedSurplusCents) < 0n, true);
});

test("expected risk costs round up and zero activity still pays fixed costs", () => {
  const data = structuredClone(sample);
  Object.assign(data.assumptions, {
    completedBountiesPerMonth: 0,
    disputeRateBasisPoints: 1,
    disputeCentsPerCase: 1,
    timeoutRateBasisPoints: 0,
  });
  const result = calculateUnitEconomics(data);
  assert.equal(result.monthlyRevenueCents, "0");
  assert.equal(result.monthlyExpectedVariableCostCents, "0");
  assert.equal(result.monthlyExpectedSurplusCents, "-19000");
  assert.equal(result.costPerCompletedBountyCentsUpperBound, "1081");
});

test("reject invalid, untrusted or misleading measured-pricing inputs", () => {
  const cases = [
    { ...sample, claim: "actual_pilot_traction" },
    { ...sample, currency: "POT" },
    { ...sample, version: "2" },
    { ...sample, secret: "unreviewed" },
    { ...sample, assumptions: { ...sample.assumptions, futureFeature: 1 } },
    {
      ...sample,
      assumptions: { ...sample.assumptions, monthlyHostingCents: -1 },
    },
    {
      ...sample,
      assumptions: { ...sample.assumptions, monthlyHostingCents: 0.01 },
    },
    {
      ...sample,
      assumptions: {
        ...sample.assumptions,
        monthlyHostingCents: Number.MAX_SAFE_INTEGER,
      },
    },
    {
      ...sample,
      assumptions: { ...sample.assumptions, disputeRateBasisPoints: 10001 },
    },
    {
      ...sample,
      assumptions: { ...sample.assumptions, timeoutRateBasisPoints: 9500 },
    },
  ];
  for (const value of cases) {
    assert.throws(
      () => calculateUnitEconomics(value),
      (error) => error instanceof EconomicsInputError,
    );
  }
});
