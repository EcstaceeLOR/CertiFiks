import { readdir, stat } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const LIMITS = Object.freeze({
  chunkBytes: 2 * 1024 * 1024,
  totalStaticBytes: 12 * 1024 * 1024,
  maxFiles: 1000,
});

/** Raw built JS/CSS budget; these are NOT Lighthouse or real-user timings. */
export function checkWebBudgetV1(files) {
  if (!Array.isArray(files) || files.length === 0 || files.length > LIMITS.maxFiles) {
    throw new Error("NO_VALID_WEB_ASSETS");
  }
  let sum = 0;
  const seen = new Set();
  for (const entry of files) {
    if (!entry || typeof entry.path !== "string" || !/\.(?:js|css)$/.test(entry.path) ||
      typeof entry.bytes !== "number" || !Number.isSafeInteger(entry.bytes) ||
      entry.bytes < 1 || seen.has(entry.path)) {
      throw new Error("INVALID_WEB_ASSET");
    }
    seen.add(entry.path);
    if (entry.bytes > LIMITS.chunkBytes) throw new Error("OVERSIZED_WEB_CHUNK");
    sum += entry.bytes;
  }
  if (sum > LIMITS.totalStaticBytes) throw new Error("OVERSIZED_STATIC_BUNDLE");
  return { rawAssetCount: files.length, rawTotalBytes: sum, rawLargestAllowed: LIMITS.chunkBytes };
}

async function collectFiles(path, relative = "") {
  const entries = await readdir(path, { withFileTypes: true });
  const result = [];
  for (const entry of entries) {
    const rel = join(relative, entry.name);
    const full = join(path, entry.name);
    if (entry.isDirectory()) {
      result.push(...await collectFiles(full, rel));
    } else if (entry.isFile() && /\.(?:js|css)$/.test(entry.name)) {
      result.push({ path: rel, bytes: (await stat(full)).size });
    }
  }
  return result;
}

export async function verifyNextBuild(project) {
  const root = resolve(project, ".next", "static");
  const files = await collectFiles(root);
  const report = checkWebBudgetV1(files);
  process.stdout.write(
    `CertiFiks build asset budget: ${report.rawAssetCount} assets, ${report.rawTotalBytes} raw bytes. No real-user timing claimed.\n`,
  );
  return report;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  verifyNextBuild(process.argv[2] ?? "apps/web").catch((error) => {
    process.stderr.write(`Asset budget check failed: ${error instanceof Error ? error.message : "invalid build"}\n`);
    process.exitCode = 1;
  });
}
