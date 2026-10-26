import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { join } from "node:path";
import { chromium } from "playwright";

const require = createRequire(import.meta.url);
const axePath = require.resolve("axe-core/axe.min.js");
const axeScript = await readFile(axePath, "utf8");
const baseUrl = process.env.CERTIFIKS_BROWSER_ORIGIN ?? "http://127.0.0.1:4100";
const routes = [
  "/",
  "/onboarding",
  "/opportunities",
  "/sponsor",
  "/developer",
  "/verifier",
  "/disputes",
  "/wallet",
  "/dashboard",
];
const widths = [375, 1280];
const summary = [];
const failures = [];
await mkdir("quality-artifacts", { recursive: true });

const browser = await chromium.launch({ headless: true });
try {
  for (const width of widths) {
    const context = await browser.newContext({
      viewport: { width, height: 860 },
      reducedMotion: "reduce",
      colorScheme: "dark",
    });
    const page = await context.newPage();
    const pageErrors = [];
    page.on("pageerror", (error) => pageErrors.push(error.message));

    for (const route of routes) {
      const slug = route === "/" ? "home" : route.slice(1);
      const response = await page.goto(baseUrl + route, {
        waitUntil: "domcontentloaded",
        timeout: 20000,
      });
      await page.locator("h1").first().waitFor({ timeout: 10000 });
      await page.addScriptTag({ content: axeScript });

      const result = await page.evaluate(async () => {
        const scan = await globalThis.axe.run(document, {
          runOnly: {
            type: "tag",
            values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"],
          },
        });
        const nav = performance.getEntriesByType("navigation")[0];
        const resources = performance.getEntriesByType("resource");
        return {
          serious: scan.violations
            .filter((v) => ["serious", "critical"].includes(v.impact))
            .map((v) => ({
              id: v.id,
              impact: v.impact,
              nodes: v.nodes.map((n) => n.target).slice(0, 6),
            })),
          allViolations: scan.violations.map((v) => v.id),
          title: document.title,
          h1Count: document.querySelectorAll("h1").length,
          width: document.documentElement.scrollWidth,
          viewport: window.innerWidth,
          ttfbMs: nav ? Math.round(nav.responseStart) : null,
          scriptBytes: resources
            .filter((v) => v.initiatorType === "script")
            .reduce((total, v) => total + (v.decodedBodySize || 0), 0),
        };
      });

      const entry = { route, width, status: response?.status(), ...result };
      summary.push(entry);
      if (entry.status !== 200) failures.push({ route, width, problem: "HTTP not 200", status: entry.status });
      if (entry.serious.length) failures.push({ route, width, problem: "WCAG serious/critical", violations: entry.serious });
      if (entry.h1Count !== 1) failures.push({ route, width, problem: "Expected one page heading", h1Count: entry.h1Count });
      if (entry.width > entry.viewport + 3) failures.push({ route, width, problem: "Horizontal page overflow", actual: entry.width });
      if (entry.ttfbMs !== null && entry.ttfbMs > 8500) failures.push({ route, width, problem: "TTFB budget exceeded", ms: entry.ttfbMs });
      if (entry.scriptBytes > 1_600_000) failures.push({ route, width, problem: "Uncompressed JS budget exceeded", bytes: entry.scriptBytes });

      if (["/", "/dashboard", "/onboarding"].includes(route)) {
        await page.screenshot({ path: join("quality-artifacts", `${slug}-${width}.png`), fullPage: true });
      }
      console.log(`${entry.status} ${route} @${width}px: ${result.serious.length} serious WCAG failures, script ${result.scriptBytes}B`);
    }

    await page.goto(baseUrl + "/", { waitUntil: "domcontentloaded" });
    await page.keyboard.press("Tab");
    const firstTab = await page.evaluate(() => document.activeElement?.textContent?.trim());
    if (firstTab !== "Skip to content") {
      failures.push({ width, problem: "First keyboard tab does not reach skip link", actual: firstTab });
    }

    await context.setOffline(true);
    await page.evaluate(() => window.dispatchEvent(new Event("offline")));
    try {
      await page.locator('[data-connection-state="offline"]').waitFor({ timeout: 3000 });
    } catch {
      failures.push({ width, problem: "Offline announcement missing" });
    }
    await context.setOffline(false);
    await page.evaluate(() => window.dispatchEvent(new Event("online")));
    try {
      await page.getByRole("button", { name: "Refresh verified data" }).waitFor({ timeout: 3000 });
    } catch {
      failures.push({ width, problem: "Recovery refresh action missing" });
    }
    if (pageErrors.length) failures.push({ width, problem: "Unhandled browser JS errors", errors: pageErrors });
    await context.close();
  }
} finally {
  await browser.close();
}

await writeFile(
  join("quality-artifacts", "browser-report.json"),
  JSON.stringify({ tested: summary.length, summary, failures }, null, 2) + "\n",
);
if (failures.length) {
  console.error(JSON.stringify(failures, null, 2));
  process.exitCode = 1;
} else {
  console.log(`PASS: ${summary.length} browser route/viewport scans, offline recovery and keyboard access`);
}
