#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { validateLiveE2EIntakeV1 } from "./live-e2e-evidence.mjs";

const path = process.argv[2];
if (!path || process.argv.length !== 3) {
  console.error("Usage: node scripts/quality/check-live-e2e-evidence.mjs /absolute/path/to/intake.json");
  console.error("No live evidence bundle is shipped. A missing bundle MUST fail.");
  process.exitCode = 2;
} else {
  try {
    const source = resolve(path);
    const doc = JSON.parse(await readFile(source, "utf8"));
    const result = await validateLiveE2EIntakeV1(doc, dirname(source));
    console.log(JSON.stringify(result, null, 2));
    console.log("External chain/GitHub/reviewer provenance remains UNVERIFIED. Never treat this result as permission to launch or pay.");
  } catch (error) {
    console.error(error instanceof Error ? error.message : "Live evidence intake failed");
    process.exitCode = 1;
  }
}
