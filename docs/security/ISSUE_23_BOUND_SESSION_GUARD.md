# Issue #23 — Active tenant-session authorization (increment)

**Status: server-only authorization foundation, not a deployed login, verified wallet signature, or funds-moving API.**

A session cookie **cannot** carry authority by itself. The new `authorizeBoundSessionV1` helper takes only server-configured policy (`organizationId`, `requiredRole`, trusted TLS origin and a known safe/unsafe request method) and requires the opaque `__Host-certi_session` credential to match an **active** PostgreSQL session. The browser never supplies membership, a GitHub identity, a wallet address, or a role.

## Security boundaries

- One syntactically valid host-only session token is extracted from a bounded Cookie header. Duplicate session cookies, malformed credentials and unconfigured/unapproved database origins are rejected.
- Unsafe actions require an exact server-approved `Origin`, Fetch Metadata indicating the same origin, and a **separate** CSRF credential. The server sends only SHA-256 digests of the opaque tokens to the protected session lookup; it never includes raw cookie/CSRF tokens in upstream bodies.
- `certifiks_authorize_session_v1` is an RPC callable only through the service-role backend. One SQL statement joins the active session, enabled user and current unrevoked membership in the exact organization/role; when required, the recorded CSRF digest must match.
- Invalid, revoked, expired, cross-tenant, role-conflicted or missing records return no authority. PostgREST outages, malformed replies and timing errors all return only `SESSION_ACCESS_DENIED`. No claims about the signed-in user's role are taken from browser JSON.
- This **does not implement or expose** a public sign-in or session creation endpoint. No wallet signature, GitHub OAuth link, private artifact route, webhook permission or transaction release is enabled by this change.

## Verification

The API test suite exercises valid sessions, exact organization/role SQL inputs, CSRF/origin attacks, cookie fixation through duplicate names, expired and ambiguous records and opaque upstream failures. PostgreSQL 16 CI applies the migration and tests active tenant membership, wrong CSRF, cross-tenant role escalation, forged arbitrator role, revocation and the inability of a browser principal to execute the private RPC.

The new guard still depends on the router **itself** choosing `unsafeMethod` correctly, using a trusted constant for the required organization and role, and verifying the source of the HTTP request. It must not be called with request-body policy values. Identity revocation immediately **after** a lookup is not solved by this API; any money-moving or security-critical operation must recheck its policy in the same committing transaction or on-chain.

## What still blocks Issue #23

The approved EIP-191/EIP-1271 signer and domain/chain verified challenge flow, atomic nonce consumption in a genuine login handler, trusted GitHub OAuth linking, session creation/rotation/logout, audited role checks on protected API methods, real multi-device recovery, actual IDOR tests across deployed tenant data, and human-authorized wallet/account verification have not been completed. Those tasks require live application configuration and independent integration review. Keep Issue #23 **OPEN** until the full acceptance criteria are proven.
