import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const home = readFileSync(new URL("../app/page.tsx", import.meta.url), "utf8");
const onboarding = readFileSync(new URL("../app/onboarding/page.tsx", import.meta.url), "utf8");
const css = readFileSync(new URL("../app/globals.css", import.meta.url), "utf8");

test("no public-facing onboarding or reward claim can bypass live prerequisites", () => {
  assert.match(home, /No live deposits, funded rewards or automated payouts/);
  assert.match(home, /loadPublishedBounties/);
  assert.match(home, /role="status"/);
  assert.match(home, /verificationProven === false/);
  assert.match(home, /No sample rewards or simulated activity/);
  assert.match(onboarding, /Onboarding is not enabled yet/);
  assert.match(onboarding, /No wallet connection or GitHub installation is performed here/);
});

test("role paths and trust disclaimers appear without fabricated activity", () => {
  for (const label of ["FOR MAINTAINERS", "FOR CONTRIBUTORS", "FOR REVIEWERS"]) {
    assert.ok(home.includes(label), label);
  }
  for (const phrase of ["Sponsor / Maintainer", "Developer / Contributor", "Verifier / Arbitrator"]) {
    assert.ok(onboarding.includes(phrase), phrase);
  }
  assert.match(home, /Live listings are unavailable/);
  assert.match(home, /No published bounties/);
});

test("design includes keyboard landmarks, visible focus and reduced-motion paths", () => {
  assert.match(home, /className="skip-link"/);
  assert.match(home, /aria-label="Primary navigation"/);
  assert.match(onboarding, /aria-label="Choose your role"/);
  assert.match(css, /:focus-visible/);
  assert.match(css, /prefers-reduced-motion/);
  assert.match(css, /prefers-color-scheme: light/);
  assert.match(css, /@media \(max-width: 640px\)/);
});

function luminance(hex) {
  const parts = hex.slice(1).match(/.{2}/g)?.map((x) => Number.parseInt(x, 16) / 255) ?? [];
  return parts.reduce(
    (sum, value, index) =>
      sum + [0.2126, 0.7152, 0.0722][index] *
        (value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4),
    0,
  );
}

test("primary body and muted token pairs meet static 4.5:1 WCAG contrast", () => {
  for (const [foreground, background] of [
    ["#f1f4f1", "#0c1519"],
    ["#b6c2c4", "#0c1519"],
    ["#132527", "#f7f8f4"],
    ["#3f575b", "#f7f8f4"],
    ["#11231a", "#b7f4b8"],
    ["#ffffff", "#185e42"],
  ]) {
    const a = luminance(foreground);
    const b = luminance(background);
    const contrast = (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
    assert.ok(contrast >= 4.5, `${foreground} on ${background}: ${contrast}`);
  }
});
