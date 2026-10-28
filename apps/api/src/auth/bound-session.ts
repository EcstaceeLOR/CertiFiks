import { createHash } from "node:crypto";
import type { UserRoleV1 } from "./session-security.js";

const COOKIE_NAME = "__Host-certi_session";
const TOKEN = /^[A-Za-z0-9_-]{43}$/;
const UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;

export class SessionAuthorizationError extends Error {
  constructor() {
    super("SESSION_ACCESS_DENIED");
    this.name = "SessionAuthorizationError";
  }
}

export interface BoundSessionRequestV1 {
  cookieHeader?: string;
  csrfHeader?: string;
  originHeader?: string;
  fetchSiteHeader?: string;
}

export interface TrustedSessionPolicyV1 {
  supabaseUrl: string;
  serviceRoleKey: string;
  trustedOrigin: string;
  organizationId: string;
  requiredRole: UserRoleV1;
  unsafeMethod: boolean;
  request?: typeof fetch;
}

function failUnless(value: unknown): asserts value {
  if (!value) throw new SessionAuthorizationError();
}

function digest(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function trustedRpc(policy: TrustedSessionPolicyV1): string {
  try {
    const url = new URL(policy.supabaseUrl);
    const origin = new URL(policy.trustedOrigin);
    failUnless(
      url.protocol === "https:" &&
        url.hostname.endsWith(".supabase.co") &&
        url.hostname !== ".supabase.co" &&
        !url.username &&
        !url.password &&
        !url.port &&
        url.pathname === "/" &&
        !url.search &&
        !url.hash &&
        origin.protocol === "https:" &&
        origin.origin === policy.trustedOrigin &&
        origin.pathname === "/" &&
        !origin.username &&
        !origin.password &&
        UUID.test(policy.organizationId) &&
        [
          "sponsor",
          "developer",
          "maintainer",
          "verifier",
          "arbitrator",
          "operator",
        ].includes(policy.requiredRole) &&
        policy.serviceRoleKey.length >= 16 &&
        typeof policy.unsafeMethod === "boolean",
    );
    return new URL("/rest/v1/rpc/certifiks_authorize_session_v1", url).href;
  } catch {
    throw new SessionAuthorizationError();
  }
}

function sessionCookie(header: string | undefined): string {
  failUnless(typeof header === "string" && header.length <= 4096);
  const cookies = header
    .split(";")
    .map((piece) => piece.trim())
    .filter((piece) => piece.startsWith(`${COOKIE_NAME}=`));
  failUnless(cookies.length === 1);
  const token = cookies[0].slice(COOKIE_NAME.length + 1);
  failUnless(TOKEN.test(token));
  return token;
}

/**
 * Authorizes only a server-trusted organization/role requirement against
 * an active session in one PostgreSQL RPC query. Callers must NEVER accept
 * organizationId or requiredRole from browser JSON or query parameters.
 *
 * This function cannot create a login, verify a wallet signature, or
 * authorize on-chain transfers. All upstream failures deny access.
 */
export async function authorizeBoundSessionV1(
  browser: BoundSessionRequestV1,
  policy: TrustedSessionPolicyV1,
): Promise<{ userId: string; expiresAt: string }> {
  const endpoint = trustedRpc(policy);
  const token = sessionCookie(browser.cookieHeader);
  let csrfDigest: string | null = null;
  if (policy.unsafeMethod) {
    failUnless(
      browser.originHeader === policy.trustedOrigin &&
        (browser.fetchSiteHeader === "same-origin" ||
          browser.fetchSiteHeader === "none") &&
        typeof browser.csrfHeader === "string" &&
        TOKEN.test(browser.csrfHeader),
    );
    csrfDigest = digest(browser.csrfHeader);
  }

  try {
    const response = await (policy.request ?? fetch)(endpoint, {
      method: "POST",
      cache: "no-store",
      redirect: "error",
      signal: AbortSignal.timeout(8000),
      headers: {
        "content-type": "application/json",
        accept: "application/json",
        apikey: policy.serviceRoleKey,
        authorization: `***      },
      body: JSON.stringify({
        p_token_digest: digest(token),
        p_organization_id: policy.organizationId,
        p_required_role: policy.requiredRole,
        p_require_csrf: policy.unsafeMethod,
        p_csrf_digest: csrfDigest,
      }),
    });
    failUnless(response.ok && !response.redirected);
    const bytes = await response.text();
    failUnless(Buffer.byteLength(bytes) <= 4096);
    const records: unknown = JSON.parse(bytes);
    failUnless(Array.isArray(records) && records.length === 1);
    const record = records[0];
    failUnless(
      record !== null &&
        typeof record === "object" &&
        Object.keys(record).sort().join("|") === "expires_at|user_id" &&
        UUID.test(record.user_id) &&
        typeof record.expires_at === "string" &&
        Number.isFinite(Date.parse(record.expires_at)) &&
        Date.parse(record.expires_at) > Date.now(),
    );
    return { userId: record.user_id, expiresAt: record.expires_at };
  } catch {
    throw new SessionAuthorizationError();
  }
}
