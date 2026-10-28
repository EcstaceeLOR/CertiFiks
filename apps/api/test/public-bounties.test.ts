import assert from "node:assert/strict";
import test from "node:test";
import { buildApp } from "../src/app.js";

const ID = "30000000-0000-4000-8000-000000000001";
const serviceRole = "server-only-test-service-role";
const record = {
  bounty_id: ID,
  repository_id: "401",
  repository_full_name: "maintainer/fix-repo",
  chain_id: "11155111",
  onchain_bounty_id: "42",
  reward_atoms: "900719925474099312345678901234",
  manifest_digest: "0x" + "ab".repeat(32),
  state: "funded",
  created_at: "2026-10-26T10:00:00.000Z",
};

test("public bounty list fetches server-filtered finalized projection with precise monetary strings", async () => {
  const calls: string[] = [];
  const mock = (async (url: string, opts?: RequestInit) => {
    calls.push(String(url));
    assert.ok(
      String(url).startsWith(
        "https://public-example.supabase.co/rest/v1/certifiks_public_bounties_v1?",
      ),
    );
    assert.equal(opts?.method, "GET");
    assert.equal(opts?.redirect, "error");
    assert.equal(
      new Headers(opts?.headers).get("Authorization"),
      `Bearer ${serviceRole}`,
    );
    return new Response(JSON.stringify([record]), { status: 200 });
  }) as typeof fetch;
  const app = buildApp({
    supabaseUrl: "https://public-example.supabase.co",
    supabaseServiceRoleKey: serviceRole,
    publicBountyFetch: mock,
  });
  try {
    const res = await app.inject({
      method: "GET",
      url: "/v1/bounties?limit=5&offset=0",
    });
    assert.equal(res.statusCode, 200, res.body);
    const body = res.json();
    assert.equal(body.items[0].rewardAtoms, record.reward_atoms);
    assert.equal(body.items[0].verificationProven, false);
    assert.equal(body.items[0].repositoryFullName, record.repository_full_name);
    assert.equal(body.items[0].manifestDigest, record.manifest_digest);
    assert.ok(!res.body.includes(serviceRole));
    assert.ok(!res.body.includes("private"));
    assert.equal(calls.length, 1);
    assert.ok(calls[0].includes("limit=5"));
    const found = await app.inject({
      method: "GET",
      url: `/v1/bounties/${ID}`,
    });
    assert.equal(found.statusCode, 200);
    assert.equal(found.json().bountyId, ID);
    assert.ok(calls[1].includes("bounty_id=eq."));
  } finally {
    await app.close();
  }
});

test("missing PostgreSQL configuration never fabricates public bounties", async () => {
  const app = buildApp({ supabaseUrl: "", supabaseServiceRoleKey: "" });
  try {
    const list = await app.inject({ method: "GET", url: "/v1/bounties" });
    assert.equal(list.statusCode, 503);
    assert.equal(list.json().error, "PUBLIC_BOUNTY_API_NOT_CONFIGURED");
    const detail = await app.inject({
      method: "GET",
      url: `/v1/bounties/${ID}`,
    });
    assert.equal(detail.statusCode, 503);
    const mutation = await app.inject({
      method: "POST",
      url: "/v1/bounties",
      payload: "{}",
    });
    assert.equal(mutation.statusCode, 404);
  } finally {
    await app.close();
  }
});

test("invalid pagination and arbitrary IDs are rejected before backend requests", async () => {
  let called = 0;
  const fake = (async () => {
    called++;
    throw new Error("should not call DB");
  }) as typeof fetch;
  const app = buildApp({
    supabaseUrl: "https://public-example.supabase.co",
    supabaseServiceRoleKey: serviceRole,
    publicBountyFetch: fake,
  });
  try {
    for (const url of [
      "/v1/bounties?limit=999",
      "/v1/bounties?limit=01",
      "/v1/bounties?offset=-1",
      "/v1/bounties?offset=10001",
      "/v1/bounties/not-a-uuid",
      "/v1/bounties/%2e%2e%2fprivate",
    ]) {
      const res = await app.inject({ method: "GET", url });
      assert.ok(
        [400, 404].includes(res.statusCode),
        url + ": " + res.statusCode,
      );
    }
    assert.equal(called, 0);
  } finally {
    await app.close();
  }
});

test("upstream access failure, malformed rows and hidden bounty never return fake success", async () => {
  let response: Response = new Response("no", { status: 403 });
  const app = buildApp({
    supabaseUrl: "https://public-example.supabase.co",
    supabaseServiceRoleKey: serviceRole,
    publicBountyFetch: (async () => response) as typeof fetch,
  });
  try {
    assert.equal(
      (await app.inject({ method: "GET", url: "/v1/bounties" })).statusCode,
      503,
    );
    response = new Response(
      JSON.stringify([{ ...record, reward_atoms: 9007199254740992 }]),
      {
        status: 200,
      },
    );
    assert.equal(
      (await app.inject({ method: "GET", url: "/v1/bounties" })).statusCode,
      503,
    );
    response = new Response(JSON.stringify([]), { status: 200 });
    const hidden = await app.inject({
      method: "GET",
      url: `/v1/bounties/${ID}`,
    });
    assert.equal(hidden.statusCode, 404);
  } finally {
    await app.close();
  }
});

test("developer search applies exact DB filters before pagination and never inflates public eligibility", async () => {
  let called = 0;
  const mock = (async (url: string, options?: RequestInit) => {
    called++;
    const u = new URL(String(url));
    assert.equal(u.searchParams.get("state"), "eq.funded");
    assert.equal(
      u.searchParams.get("repository_full_name"),
      "eq.maintainer/fix-repo",
    );
    assert.equal(u.searchParams.get("limit"), "12");
    assert.equal(u.searchParams.get("offset"), "24");
    assert.equal(
      new Headers(options?.headers).get("Authorization"),
      `Bearer ${serviceRole}`,
    );
    return new Response(JSON.stringify([record]), { status: 200 });
  }) as typeof fetch;
  const app = buildApp({
    supabaseUrl: "https://public-example.supabase.co",
    supabaseServiceRoleKey: serviceRole,
    publicBountyFetch: mock,
  });
  try {
    const res = await app.inject({
      method: "GET",
      url: "/v1/bounties?limit=12&offset=24&state=funded&repo=maintainer%2Ffix-repo",
    });
    assert.equal(res.statusCode, 200, res.body);
    assert.equal(called, 1);
    assert.equal(res.json().items[0].verificationProven, false);
    assert.equal(res.json().items[0].rewardAtoms, record.reward_atoms);
    assert.equal(res.json().page.offset, 24);
  } finally {
    await app.close();
  }
});

test("developer search rejects unsupported states and dangerous repository filter syntax before DB", async () => {
  let called = 0;
  const app = buildApp({
    supabaseUrl: "https://public-example.supabase.co",
    supabaseServiceRoleKey: serviceRole,
    publicBountyFetch: (async () => {
      called++;
      return new Response(JSON.stringify([]), { status: 200 });
    }) as typeof fetch,
  });
  try {
    for (const url of [
      "/v1/bounties?state=verified",
      "/v1/bounties?state=draft",
      "/v1/bounties?repo=any%2Fteam%2Cstate.eq.funded",
      "/v1/bounties?repo=%3D%3D%2Funsafe",
      "/v1/bounties?repo=owner%2Frepo%2Cfoo",
      "/v1/bounties?repo=owner%2Frepo&state=funded&state=settled",
    ]) {
      const result = await app.inject({ method: "GET", url });
      assert.equal(result.statusCode, 400, url + " -> " + result.statusCode);
      assert.equal(result.json().error, "PUBLIC_BOUNTY_INVALID_FILTER");
    }
    assert.equal(called, 0);
  } finally {
    await app.close();
  }
});

test("public history uses only whitelisted deterministic sorting and returns bounded CSV", async () => {
  const requests: URL[] = [];
  const app = buildApp({
    supabaseUrl: "https://public-example.supabase.co",
    supabaseServiceRoleKey: serviceRole,
    publicBountyFetch: (async (url: string, options?: RequestInit) => {
      requests.push(new URL(url));
      assert.equal(options?.method, "GET");
      assert.equal(options?.redirect, "error");
      assert.equal(
        new Headers(options?.headers).get("Authorization"),
        `Bearer ${serviceRole}`,
      );
      return new Response(JSON.stringify([record]), { status: 200 });
    }) as typeof fetch,
  });
  try {
    const older = await app.inject({
      method: "GET",
      url: "/v1/bounties?sort=oldest",
    });
    assert.equal(older.statusCode, 200, older.body);
    assert.equal(
      requests[0].searchParams.get("order"),
      "created_at.asc,bounty_id.asc",
    );
    const alpha = await app.inject({
      method: "GET",
      url: "/v1/bounties?sort=repository",
    });
    assert.equal(alpha.statusCode, 200, alpha.body);
    assert.equal(
      requests[1].searchParams.get("order"),
      "repository_full_name.asc,bounty_id.asc",
    );

    const csv = await app.inject({
      method: "GET",
      url: "/v1/bounties/export.csv?state=funded&repo=maintainer%2Ffix-repo&sort=newest&offset=20",
    });
    assert.equal(csv.statusCode, 200, csv.body);
    assert.match(csv.headers["content-type"] as string, /^text\/csv/);
    assert.match(csv.body, /bounty_id,repository,state,created_at/);
    assert.match(csv.body, /maintainer\/fix-repo/);
    assert.match(csv.body, /900719925474099312345678901234/);
    assert.ok(!csv.body.includes(serviceRole));
    assert.equal(requests[2].searchParams.get("state"), "eq.funded");
    assert.equal(
      requests[2].searchParams.get("repository_full_name"),
      "eq.maintainer/fix-repo",
    );
    assert.equal(requests[2].searchParams.get("limit"), "50");
    assert.equal(requests[2].searchParams.get("offset"), "20");
  } finally {
    await app.close();
  }
});

test("public history rejects unknown sorting and CSV filter injection without querying DB", async () => {
  let calls = 0;
  const app = buildApp({
    supabaseUrl: "https://public-example.supabase.co",
    supabaseServiceRoleKey: serviceRole,
    publicBountyFetch: (async () => {
      calls++;
      return new Response(JSON.stringify([]), { status: 200 });
    }) as typeof fetch,
  });
  try {
    for (const url of [
      "/v1/bounties?sort=reward_atoms.desc",
      "/v1/bounties?sort=reward_high",
      "/v1/bounties/export.csv?sort=state.desc",
      "/v1/bounties/export.csv?repo=x%2Fy%2Cor.%28true%29",
      "/v1/bounties/export.csv?offset=-5",
      "/v1/bounties/export.csv?limit=10000",
    ]) {
      const response = await app.inject({ method: "GET", url });
      assert.equal(response.statusCode, 400, url + ": " + response.body);
    }
    assert.equal(calls, 0);
  } finally {
    await app.close();
  }
});

test("public lifecycle query allowlists reject inherited sort names and unknown filters before database access", async () => {
  let dbCalls = 0;
  const app = buildApp({
    supabaseUrl: "https://public-example.supabase.co",
    supabaseServiceRoleKey: serviceRole,
    publicBountyFetch: (async () => {
      dbCalls += 1;
      return new Response(JSON.stringify([record]), { status: 200 });
    }) as typeof fetch,
  });
  try {
    for (const url of [
      "/v1/bounties?sort=constructor",
      "/v1/bounties?sort=toString",
      "/v1/bounties?sort=__proto__",
      "/v1/bounties?include_private=true",
      "/v1/bounties?foo=bar",
      "/v1/bounties/export.csv?sort=constructor",
      "/v1/bounties/export.csv?include_private=true",
      `/v1/bounties/${ID}?include_private=true`,
    ]) {
      const response = await app.inject({ method: "GET", url });
      assert.equal(response.statusCode, 400, url + ": " + response.body);
      assert.ok(
        [
          "PUBLIC_BOUNTY_INVALID_QUERY",
          "PUBLIC_BOUNTY_INVALID_FILTER",
        ].includes(response.json().error),
      );
    }
    assert.equal(dbCalls, 0);
  } finally {
    await app.close();
  }
});

test("capability states distinguish configured transport from unavailable money moving actions", async () => {
  const cases = [
    {
      config: {
        supabaseUrl: "",
        supabaseServiceRoleKey: "",
        webhookSecret: "",
        webhookJournalDirectory: "",
      },
      bountyState: "not_configured",
      webhookState: "not_configured",
    },
    {
      config: {
        supabaseUrl: "https://public-example.supabase.co",
        supabaseServiceRoleKey: serviceRole,
        webhookSecret: "synthetic-webhook-secret-with-enough-entropy",
      },
      bountyState: "configured_unverified",
      webhookState: "configured_unverified",
    },
  ];
  for (const scenario of cases) {
    const app = buildApp({ ...scenario.config, production: true });
    try {
      const response = await app.inject({
        method: "GET",
        url: "/v1/capabilities",
      });
      assert.equal(response.statusCode, 200, response.body);
      assert.equal(response.headers["cache-control"], "no-store");
      const body = response.json();
      assert.equal(body.version, "1");
      assert.equal(body.productReady, false);
      assert.equal(body.settlementReady, false);
      assert.equal(
        body.capabilities.publicBounties.state,
        scenario.bountyState,
      );
      assert.equal(
        body.capabilities.githubWebhookIngestion.state,
        scenario.webhookState,
      );
      assert.equal(body.capabilities.githubWebhookIngestion.verifiedFix, false);
      for (const key of [
        "walletSignIn",
        "githubOAuth",
        "bountyFunding",
        "candidateSubmission",
        "signedVerification",
        "disputes",
        "withdrawals",
        "privateEvidence",
      ]) {
        assert.equal(body.capabilities[key].state, "not_available", key);
      }
      assert.ok(!response.body.includes(serviceRole));
      assert.ok(!response.body.includes(scenario.config.webhookSecret));
    } finally {
      await app.close();
    }
  }
});
