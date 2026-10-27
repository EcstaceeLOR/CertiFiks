import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

export class EconomicsInputError extends Error {
  constructor() {
    super("ECONOMICS_INVALID_INPUT");
    this.name = "EconomicsInputError";
  }
}

const FIELDS = [
  "completedBountiesPerMonth",
  "sponsorFeeCentsPerCompletedBounty",
  "monthlyHostingCents",
  "monthlyMonitoringCents",
  "monthlyBackupCents",
  "monthlyComplianceCents",
  "verificationRunsPerCompleted",
  "retryRunsPerCompleted",
  "verificationRunCents",
  "independentReviewerCentsPerCompleted",
  "artifactRetentionCentsPerCompleted",
  "rpcCentsPerCompleted",
  "supportCentsPerCompleted",
  "disputeRateBasisPoints",
  "disputeCentsPerCase",
  "timeoutRateBasisPoints",
  "timeoutCentsPerCase",
];

const MAX = 1_000_000_000;

function failUnless(ok) {
  if (!ok) throw new EconomicsInputError();
}

function exactKeys(obj, keys) {
  failUnless(obj !== null && typeof obj === "object" && !Array.isArray(obj));
  failUnless(Object.keys(obj).sort().join("|") === [...keys].sort().join("|"));
}

function cents(value) {
  failUnless(Number.isSafeInteger(value) && value >= 0 && value <= MAX);
  return BigInt(value);
}

function ceilDivide(numerator, denominator) {
  return (numerator + denominator - 1n) / denominator;
}

/**
 * Planning math only; all prices are input assumptions, not live charges.
 * Exact integer-cent arithmetic prevents unsafe floating-point fee rounding.
 */
export function calculateUnitEconomics(input) {
  exactKeys(input, ["version", "claim", "currency", "assumptions"]);
  failUnless(
    input.version === "1" &&
      input.claim === "synthetic_planning_only" &&
      input.currency === "USD",
  );
  exactKeys(input.assumptions, FIELDS);
  const a = {};
  for (const field of FIELDS) a[field] = cents(input.assumptions[field]);
  failUnless(
    a.disputeRateBasisPoints <= 10_000n &&
      a.timeoutRateBasisPoints <= 10_000n &&
      a.disputeRateBasisPoints + a.timeoutRateBasisPoints <= 10_000n,
  );

  const fixed =
    a.monthlyHostingCents +
    a.monthlyMonitoringCents +
    a.monthlyBackupCents +
    a.monthlyComplianceCents;
  const runs = a.verificationRunsPerCompleted + a.retryRunsPerCompleted;
  const direct =
    runs * a.verificationRunCents +
    a.independentReviewerCentsPerCompleted +
    a.artifactRetentionCentsPerCompleted +
    a.rpcCentsPerCompleted +
    a.supportCentsPerCompleted;
  // 10,000 basis points = 100%; the numerator is expressed in cent-bps.
  const variableBp =
    direct * 10_000n +
    a.disputeRateBasisPoints * a.disputeCentsPerCase +
    a.timeoutRateBasisPoints * a.timeoutCentsPerCase;
  const count = a.completedBountiesPerMonth;
  const fee = a.sponsorFeeCentsPerCompletedBounty;
  const revenue = fee * count;
  const variableCost = ceilDivide(variableBp * count, 10_000n);
  const monthlyCost = fixed + variableCost;
  const marginBp = fee * 10_000n - variableBp;
  const breakEven =
    marginBp > 0n ? ceilDivide(fixed * 10_000n, marginBp).toString() : null;

  return {
    version: "1",
    claim: "synthetic_planning_only",
    currency: "USD",
    assumptionsAreMeasured: false,
    feeIsLive: false,
    costPerCompletedBountyCentsUpperBound: ceilDivide(
      variableBp,
      10_000n,
    ).toString(),
    directCostPerCompletedBountyCents: direct.toString(),
    expectedDisputeAndTimeoutCostCentBasisPoints: (
      variableBp -
      direct * 10_000n
    ).toString(),
    fixedMonthlyCents: fixed.toString(),
    assumedCompletedBountiesPerMonth: count.toString(),
    monthlyRevenueCents: revenue.toString(),
    monthlyExpectedVariableCostCents: variableCost.toString(),
    monthlyExpectedTotalCostCents: monthlyCost.toString(),
    monthlyExpectedSurplusCents: (revenue - monthlyCost).toString(),
    breakEvenCompletedBountiesPerMonth: breakEven,
    profitablePerIncrement: marginBp > 0n,
    productionBillingEnabled: false,
    adoptionValidated: false,
  };
}

async function main() {
  if (process.argv.length !== 3) {
    process.stderr.write(
      "Usage: node scripts/business/unit-economics.mjs INPUT.json\n",
    );
    process.exitCode = 2;
    return;
  }
  try {
    const bytes = await readFile(process.argv[2], "utf8");
    const result = calculateUnitEconomics(JSON.parse(bytes));
    process.stdout.write(JSON.stringify(result, null, 2) + "\n");
  } catch {
    process.stderr.write("ECONOMICS_INVALID_INPUT\n");
    process.exitCode = 1;
  }
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  await main();
}
