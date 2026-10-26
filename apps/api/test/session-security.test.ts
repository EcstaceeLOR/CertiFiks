import assert from "node:assert/strict";
import test from "node:test";
import {
  assertChallengeUsableV1,
  assertCsrfTokenV1,
  clearSessionCookieV1,
  generateSessionCredentialsV1,
  generateWalletChallengeV1,
  requireRoleV1,
  secureSessionCookieV1,
} from "../src/auth/session-security.js";

const wallet = "0x" + "ab".repeat(20);
const origin = "https://certifiks.example";
const now = 1793000000;
const config = {
  allowedOrigins: [origin],
  allowedChainIds: ["1", "11155111"],
  nowSeconds: now,
};

test("creates unique cryptographic wallet challenges bound to approved domain and chain", () => {
  const input = { wallet, origin, chainId: "1" };
  const a = generateWalletChallengeV1(input, config);
  const b = generateWalletChallengeV1(input, config);
  assert.notEqual(a.nonce, b.nonce);
  assert.notEqual(a.nonceDigest, b.nonceDigest);
  assert.ok(a.message.includes(`Chain ID: 1`));
  assert.ok(a.message.includes(`URI: ${origin}`));
  assert.ok(a.message.includes(`Nonce: ${a.nonce}`));
  assertChallengeUsableV1(a, { ...input, message: a.message, nonce: a.nonce }, now + 10);
  assert.throws(() => assertChallengeUsableV1(
    a, { ...input, message: a.message, nonce: a.nonce }, now + 301,
  ), /expired/);
  assert.throws(() => assertChallengeUsableV1(
    a, { ...input, chainId: "11155111", message: a.message, nonce: a.nonce }, now + 10,
  ), /binding/);
});

test("cross-domain, attacker wallet and unapproved chain are rejected", () => {
  assert.throws(() => generateWalletChallengeV1(
    { wallet, origin: "https://phishing.example", chainId: "1" }, config,
  ), /domain/);
  assert.throws(() => generateWalletChallengeV1(
    { wallet, origin, chainId: "2" }, config,
  ), /chain/);
  assert.throws(() => generateWalletChallengeV1(
    { wallet: "0x" + "FF".repeat(20), origin, chainId: "1" }, config,
  ), /wallet/);
  assert.throws(() => generateWalletChallengeV1(
    { wallet, origin: "http://certifiks.example", chainId: "1" }, config,
  ), /origin/);
});

test("opaque credentials rotate and secure cookies do not expose tokens to scripts", () => {
  const a = generateSessionCredentialsV1();
  const b = generateSessionCredentialsV1();
  assert.notEqual(a.sessionToken, b.sessionToken);
  assert.notEqual(a.csrfToken, b.csrfToken);
  assert.match(a.sessionTokenDigest, /^[a-f0-9]{64}$/);
  assert.match(a.csrfTokenDigest, /^[a-f0-9]{64}$/);
  const cookie = secureSessionCookieV1(a.sessionToken, { production: true });
  assert.match(cookie, /^__Host-certi_session=/);
  for (const flag of ["HttpOnly", "Secure", "SameSite=Strict", "Path=/"]) {
    assert.ok(cookie.includes(flag));
  }
  assert.match(clearSessionCookieV1(), /Max-Age=0/);
  assert.throws(() => secureSessionCookieV1(a.sessionToken, { production: false }), /TLS/);
  assertCsrfTokenV1(a.csrfToken, a.csrfTokenDigest);
  assert.throws(() => assertCsrfTokenV1(b.csrfToken, a.csrfTokenDigest), /CSRF/);
});

test("server-trusted role and expiration are mandatory", () => {
  const active = {
    active: true,
    expiresAt: "2026-11-20T00:00:00.000Z",
    trustedRoles: ["developer" as const],
  };
  requireRoleV1(active, "developer", new Date("2026-10-26T10:00:00.000Z"));
  assert.throws(() => requireRoleV1(active, "arbitrator", new Date("2026-12-20T00:00:00.000Z")), /inactive or expired/);
  assert.throws(() => requireRoleV1(active, "arbitrator", new Date("2026-10-26T10:00:00.000Z")), /privilege/);
  assert.throws(() => requireRoleV1({ ...active, active: false },
    "developer", new Date("2026-10-26T10:00:00.000Z")), /inactive/);
});
