import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const base = JSON.parse(
  readFileSync(join(root, "protocol/openapi.base.json"), "utf8"),
);
const sources = {
  ManifestV1: "bounty-manifest",
  CandidateAttemptV1: "candidate-attempt",
  VerificationReportV1: "verification-report",
  DisputeCaseV1: "dispute-case",
  ChainEventV1: "chain-event",
};
for (const [schemaName, fileBase] of Object.entries(sources)) {
  const contents = readFileSync(
    join(root, "packages/shared/src/schemas/v1", fileBase + ".schema.json"),
    "utf8",
  );
  base.components.schemas[schemaName] = JSON.parse(contents);
}
const outputPath = join(root, "protocol/openapi.v1.json");
const generated = JSON.stringify(base, null, 2) + "\n";
if (process.argv.includes("--check")) {
  if (
    JSON.stringify(JSON.parse(readFileSync(outputPath, "utf8"))) !==
    JSON.stringify(base)
  ) {
    console.error(
      "OpenAPI is stale. Run npm run protocol:generate and commit generated output.",
    );
    process.exit(1);
  }
  console.log(
    "PASS: OpenAPI matches checked-in JSON schemas and base specification",
  );
} else {
  writeFileSync(outputPath, generated);
  console.log("Updated protocol/openapi.v1.json from schema source");
}
