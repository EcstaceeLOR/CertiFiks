import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import {
  authorizeBoundSessionV1,
  SessionAuthorizationError,
  type TrustedSessionPolicyV1,
} from "../src/auth/bound-session.js";

const organizationId = "20000000-0000-4000-8000-000000000001";
const userId = "10000000-0000-4000-8000-000000000001";
const token = "a".repeat(43);
const csrf = "b".repeat(43);
const cookie = `other=unrelated; __Host-certi_session=${token}`;
const trustedOrigin = "https://certifiks.example";
const sha = (value: string) =>
  createHash("sha256").update(value).digest("hex");

function setup(reply: unknown = [{
  user_id: userId,
  expires_at: "2099-01-01T00:00:00.000Z",
}]) {
  const requests: unknown[] = [];
  const policy: TrustedSessionPolicyV1 = {
    supabaseUrl: "https://certifiks-ci.supabase.co",
    serviceRoleKey: "synthetic-server-only-key-not-real",
    trustedOrigin,
    organizationId,
    requiredRole: "developer",
    unsafeMethod: false,
    request: (async (url: RequestInfo | URL, init?: RequestInit) => {
      requests.push({ url, init });
      assert.equal(
        String(url),
        "https://certifiks-ci.supabase.co/rest/v1/rpc/certifiks_authorize_session_v1",
      );
      assert.equal(init?.redirect, "error");
      assert.equal(init?.cache, "no-store");
      assert.equal(init?.method, "POST");
      assert.equal(
        (init?.headers as Record<string, string>)?.apikey,
        policy.serviceRoleKey,
      );
      return new Response(JSON.stringify(reply), { status: 200 });
    }) as typeof fetch,
  };
  return { policy, requests };
}

test("server-side role lookup binds opaque cookie to exact tenant and required role", async () => {
  const { policy, requests } = setup();
  const result = await authorizeBoundSessionV1({ cookieHeader: cookie }, policy);
  assert.deepEqual(result, {
    userId,
    expiresAt: "2099-01-01T00:00:00.000Z",
  });
  assert.equal(requests.length, 1);
  const { init } = requests[0] as { init: RequestInit };
  const body = JSON.parse(String(init.body));
  assert.deepEqual(body, {
    p_token_digest: sha(token),
    p_organization_id: organizationId,
    p_required_role: "developer",
    p_require_csrf: false,
    p_csrf_digest: null,
  });
  assert.ok(!String(init.body).includes(token));
});

test("unsafe actions require exact origin, same-origin browser and separate CSRF", async () => {
  const { policy, requests } = setup();
  const browser = {
    cookieHeader: cookie,
    originHeader: trustedOrigin,
    fetchSiteHeader: "same-origin",
    csrfHeader: csrf,
  };
  const result = await authorizeBoundSessionV1(browser, {
    ...policy,
    unsafeMethod: true,
  });
  assert.equal(result.userId, userId);
  const { init } = requests[0] as { init: RequestInit };
  const params = JSON.parse(String(init.body));
  assert.equal(params.p_csrf_digest, sha(csrf));
  assert.equal(params.p_require_csrf, true);

  for (const denied of [
    { ...browser, originHeader: "https://phishing.example" },
    { ...browser, fetchSiteHeader: "same-site" },
    { ...browser, fetchSiteHeader: "cross-site" },
    { ...browser, csrfHeader: undefined },
    { ...browser, csrfHeader: "x" },
    { ...browser, cookieHeader: `${cookie}; __Host-certi_session=${token}` },
  ]) {
    await assert.rejects(
      authorizeBoundSessionV1(denied, { ...policy, unsafeMethod: true }),
      SessionAuthorizationError,
    );
  }
  assert.equal(requests.length, 1);
});

test("revoked/expired/missing role, ambiguous rows and upstream errors deny access", async () => {
  for (const response of [
    [],
    [{ user_id: userId, expires_at: "2000-01-01T00:00:00Z" }],
    [
      { user_id: userId, expires_at: "2099-01-01T00:00:00Z" },
      { user_id: userId, expires_at: "2099-01-01T00:00:00Z" },
    ],
    [{ user_id: userId, expires_at: "2099-01-01T00:00:00Z", role: "operator" }],
  ]) {
    await assert.rejects(
      authorizeBoundSessionV1({ cookieHeader: cookie }, setup(response).policy),
      SessionAuthorizationError,
    );
  }
  const { policy } = setup();
  await assert.rejects(
    authorizeBoundSessionV1(
      { cookieHeader: cookie },
      {
        ...policy,
        request: (async () => new Response("private upstream error", {
          status: 503,
        })) as typeof fetch,
      },
    ),
    (error: unknown) =>
      error instanceof SessionAuthorizationError &&
      error.message === "SESSION_ACCESS_DENIED",
  );
});

test("no unapproved database origin, stolen cookies or untrusted role configuration", async () => {
  const { policy, requests } = setup();
  for (const invalid of [
    { policy: { ...policy, supabaseUrl: "https://attacker.invalid" } },
    { policy: { ...policy, supabaseUrl: "http://certifiks-ci.supabase.co" } },
    { policy: { ...policy, trustedOrigin: "http://certifiks.example" } },
    { policy: { ...policy, requiredRole: "custodian" as never } },
    { policy: { ...policy, organizationId: "not-a-tenant" } },
    { cookieHeader: `__Host-certi_session=${token}; __Host-certi_session=${token}` },
    { cookieHeader: "session=browser-faked" },
  ]) {
    await assert.rejects(
      authorizeBoundSessionV1(
        { cookieHeader: invalid.cookieHeader ?? cookie },
        invalid.policy ?? policy,
      ),
      SessionAuthorizationError,
    );
  }
  assert.equal(requests.length, 0);
});
