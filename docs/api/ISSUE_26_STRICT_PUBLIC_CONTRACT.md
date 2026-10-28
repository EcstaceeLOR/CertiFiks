# Issue #26 — Strict public API contracts and truthful capabilities

**Status:** this increment hardens existing read-only lifecycle endpoints. It does not activate authenticated funding, wallet sessions, private artifacts, verification jobs, disputes or withdrawals.

## `GET /v1/capabilities`

A new no-store JSON contract lets frontend onboarding distinguish **server configuration** from actual service availability:

- `publicBounties.state` is `configured_unverified` only if both internal Supabase configuration values exist; it otherwise returns `not_configured`. Being configured does **not** mean the database is reachable or that an independently finalized bounty exists.
- `githubWebhookIngestion.state` is `configured_unverified` only with configured webhook secret and durable journal on production; it is **not** a verified GitHub identity or accepted fix.
- All unfinished customer-facing flows report `not_available`: wallet sign-in, GitHub OAuth, bounty funding, candidate submission, signed verification, disputes, native withdrawals, and private evidence.
- `productReady` and `settlementReady` remain `false` for every configuration. No secret, backend URL, token or private tenant data is returned. Use `GET /readyz` separately to probe transport health; even that **cannot** certify escrow readiness.

Example safe response shape:

```json
{
  "version": "1",
  "productReady": false,
  "settlementReady": false,
  "capabilities": {
    "publicBounties": {"state": "not_configured", "readOnly": true},
    "githubWebhookIngestion": {"state": "not_configured", "readOnly": false, "verifiedFix": false},
    "walletSignIn": {"state": "not_available"},
    "githubOAuth": {"state": "not_available"},
    "bountyFunding": {"state": "not_available"},
    "candidateSubmission": {"state": "not_available"},
    "signedVerification": {"state": "not_available"},
    "disputes": {"state": "not_available"},
    "withdrawals": {"state": "not_available"},
    "privateEvidence": {"state": "not_available"}
  },
  "note": "Server configuration is not proof of authenticated service availability, settlement finality or production readiness."
}
```

## Query parsing changes

The `/v1/bounties` read-only JSON list and `/v1/bounties/export.csv` exports now reject any unsupported query field. Detail `/v1/bounties/{bountyId}` rejects query parameters entirely, eliminating silently ignored request scope. Sort whitelists now use `Object.hasOwn` instead of the JavaScript `in` operator: `sort=constructor`, `sort=toString`, and `sort=__proto__` cannot masquerade as declared sort values through the object prototype. Even direct internal callers of `PublicBountyClient` fail closed. Invalid filters return 400 before any privileged PostgREST request.

Synthetic Fastify injection tests cover both configured/unconfigured capability states and unsupported or inherited query fields. They do not create bounties or establish any product-ready service.

**Full Issue #26 acceptance remains OPEN** until real wallet/GitHub login (#23), correct closed-form authorization for each role and money-moving action, a complete versioned OpenAPI contract aligned to actual deployed operations, workflow audit/idempotency, and verified human E2E transactions are operational.
