# Issue #23 — Atomic, non-extending authentication session rotation

**Status: PostgreSQL/session lifetime foundation only. This is not a live EVM wallet-signature verifier, GitHub OAuth integration, authenticated HTTP endpoint, logged-in account or authorization to settle funds.**

The existing `session-security.ts` generates random 256-bit opaque session and CSRF tokens and Secure/HttpOnly/SameSite=Strict cookies. Existing PostgreSQL tables store only token digests. Until an EIP-191/EIP-1271 wallet proof and independent GitHub account linking are available, the app must **not** present these primitives as working login.

The new migration `202610270003_auth_session_rotation.sql` makes a session refresh conditional and atomic:

- Server-only `certifiks_rotate_auth_session_once` requires the exact *existing* session-token SHA-256 digest and CSRF SHA-256 digest. It row-locks/revokes the active old session and creates a **new**, distinct token/CSRF digest with the **same** authenticated subject in one transaction.
- Unique rotation-parent index prevents a second replacement for the same old session, and replaying an already rotated or expired parent returns **false**. The new session may **not** extend the old session's original expiry. A longer session requires a fresh wallet authentication.
- Session identity, CSRF digest, subject, creation/expiry timestamps and rotation lineage are immutable. Only one-way revocation is possible. An invalid refresh rolls back the attempted parent revocation.
- SQL grants execution only to the service role. Anonymous/browser roles cannot call this RPC or inspect session data. A trusted HTTP handler must still validate actual opaque credentials, CSRF, origin, current user/wallet and role permissions **before** calling it.

PostgreSQL CI fixtures verify one successful rotation, old-token invalidation, no two active children, CSRF mismatch, overlong lifetime failure without accidental logout, immutable subjects, one-way revocation and a forged browser role.

## Full acceptance still missing

1. A real wallet/contract-wallet signature verifier bound to the exact server-stored challenge, domain, wallet address and verified chain; atomic nonce redemption and secure session creation after proof.
2. A deployed HTTPS cookie login/logout/refresh API with CSRF, token rotation, revocation and simultaneous-device tests.
3. Live GitHub OAuth identity linking with consent, verified installation ownership, account disconnection/recovery and deletion/redaction compliance.
4. Enforced tenant authorization, role conflicts, private-artifact protection, IDOR attack tests and professional security review using non-synthetic accounts.

**Issue #23 stays OPEN** until these verified, deployed end-to-end user actions succeed. Passing SQL regression tests alone does not log in a real person.
