import { createHash, randomBytes, timingSafeEqual } from "node:crypto";

/**
 * This is challenge/session *infrastructure*, never a wallet authenticator.
 * Only an audited Ethereum EIP-191/EIP-1271 signature verifier with chain and
 * address binding plus atomic DB nonce redemption may create live sessions.
 */
const WALLET = /^0x[a-f0-9]{40}$/;
const NONCE = /^[A-Za-z0-9_-]{16,64}$/;
const SESSION = /^[A-Za-z0-9_-]{43}$/;
const MAX_CHALLENGE_SECONDS = 300;
const MAX_SESSION_SECONDS = 24 * 3600;

export interface LoginChallengeV1 {
  wallet: string;
  origin: string;
  chainId: string;
  nonce: string;
  issuedAt: string;
  expiresAt: string;
  message: string;
  nonceDigest: string;
}

function check(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(`AUTH_REJECTED: ${message}`);
}

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function unixDate(seconds: number): string {
  return new Date(seconds * 1000).toISOString();
}

/** No caller-supplied nonce, timestamp, domain, or chain identifier. */
export function generateWalletChallengeV1(
  identity: { wallet: string; origin: string; chainId: string },
  options: {
    allowedOrigins: string[];
    allowedChainIds: string[];
    nowSeconds?: number;
  },
): LoginChallengeV1 {
  check(
    WALLET.test(identity.wallet),
    "wallet must be canonical lowercase EVM address",
  );
  check(
    /^[1-9][0-9]*$/.test(identity.chainId) &&
      options.allowedChainIds.includes(identity.chainId),
    "unapproved chain",
  );
  const u = new URL(identity.origin);
  check(
    (u.protocol === "https:" ||
      (u.protocol === "http:" && u.hostname === "localhost")) &&
      !u.username &&
      !u.password &&
      !u.search &&
      !u.hash &&
      u.pathname === "/",
    "invalid origin",
  );
  check(options.allowedOrigins.includes(u.origin), "domain not approved");
  const now = options.nowSeconds ?? Math.floor(Date.now() / 1000);
  check(Number.isSafeInteger(now) && now > 0, "invalid server time");
  const nonce = randomBytes(24).toString("base64url");
  const issuedAt = unixDate(now);
  const expiresAt = unixDate(now + MAX_CHALLENGE_SECONDS);
  const message = [
    `${u.host} wants you to sign in with your Ethereum account:`,
    identity.wallet,
    "",
    "Sign in to CertiFiks. This request does not authorize a transaction.",
    "",
    `URI: ${u.origin}`,
    "Version: 1",
    `Chain ID: ${identity.chainId}`,
    `Nonce: ${nonce}`,
    `Issued At: ${issuedAt}`,
    `Expiration Time: ${expiresAt}`,
  ].join("\n");
  return {
    wallet: identity.wallet,
    origin: u.origin,
    chainId: identity.chainId,
    nonce,
    issuedAt,
    expiresAt,
    message,
    nonceDigest: sha256(nonce),
  };
}

/** Inputs must be loaded from the original, unconsumed server-side challenge. */
export function assertChallengeUsableV1(
  challenge: LoginChallengeV1,
  posted: {
    wallet: string;
    origin: string;
    chainId: string;
    message: string;
    nonce: string;
  },
  nowSeconds = Math.floor(Date.now() / 1000),
): void {
  check(NONCE.test(challenge.nonce), "invalid challenge nonce");
  check(
    nowSeconds < Date.parse(challenge.expiresAt) / 1000 &&
      nowSeconds >= Date.parse(challenge.issuedAt) / 1000 - 60,
    "expired or future challenge",
  );
  check(
    challenge.wallet === posted.wallet &&
      challenge.origin === posted.origin &&
      challenge.chainId === posted.chainId &&
      challenge.message === posted.message &&
      challenge.nonce === posted.nonce,
    "challenge binding mismatch",
  );
  check(
    challenge.nonceDigest === sha256(posted.nonce),
    "nonce commitment mismatch",
  );
}

/**
 * After signed proof, rotate *both* session and CSRF credentials. Only hashes
 * may enter the session database. Never accept IDs/roles from browser JSON.
 */
export function generateSessionCredentialsV1(): {
  sessionToken: string;
  sessionTokenDigest: string;
  csrfToken: string;
  csrfTokenDigest: string;
} {
  const sessionToken = randomBytes(32).toString("base64url");
  const csrfToken = randomBytes(32).toString("base64url");
  return {
    sessionToken,
    sessionTokenDigest: sha256(sessionToken),
    csrfToken,
    csrfTokenDigest: sha256(csrfToken),
  };
}

export function secureSessionCookieV1(
  token: string,
  options: { production: boolean; maxAgeSeconds?: number },
): string {
  check(SESSION.test(token), "invalid session credential");
  const age = options.maxAgeSeconds ?? 3600;
  check(
    Number.isSafeInteger(age) && age > 0 && age <= MAX_SESSION_SECONDS,
    "session lifetime out of range",
  );
  check(options.production, "secure production cookie requires TLS deployment");
  return `__Host-certi_session=${token}; Path=/; Max-Age=${age}; HttpOnly; Secure; SameSite=Strict`;
}

export function clearSessionCookieV1(): string {
  return "__Host-certi_session=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Strict";
}

export function assertCsrfTokenV1(
  candidate: string,
  expectedDigest: string,
): void {
  check(
    SESSION.test(candidate) && /^[a-f0-9]{64}$/.test(expectedDigest),
    "invalid CSRF token format",
  );
  check(
    timingSafeEqual(
      Buffer.from(sha256(candidate), "hex"),
      Buffer.from(expectedDigest, "hex"),
    ),
    "invalid CSRF token",
  );
}

export type UserRoleV1 =
  | "sponsor"
  | "developer"
  | "maintainer"
  | "verifier"
  | "arbitrator"
  | "operator";

export function requireRoleV1(
  session: { active: boolean; expiresAt: string; trustedRoles: UserRoleV1[] },
  role: UserRoleV1,
  now = new Date(),
): void {
  check(
    session.active &&
      Number.isFinite(Date.parse(session.expiresAt)) &&
      Date.parse(session.expiresAt) > now.getTime(),
    "inactive or expired session",
  );
  check(
    Array.isArray(session.trustedRoles) && session.trustedRoles.includes(role),
    "insufficient privilege",
  );
}
