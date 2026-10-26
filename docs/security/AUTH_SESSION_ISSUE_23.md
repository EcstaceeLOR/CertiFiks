# Issue #23 — Wallet and GitHub authentication foundation

This change adds cryptographically random domain- and chain-bound EVM-wallet sign-in challenges, strict five-minute expiry checks, SHA-256 nonce hashes, opaque 256-bit session/CSRF token generation, Secure HttpOnly SameSite=Strict host-only cookies, role-check helpers and PostgreSQL tables for identity, signed challenge redemption, user sessions and per-organization memberships.

## Security expectations

- Choose approved origins and chains from **server-only** configuration. Do not accept a browser-chosen network/domain. Generate a new nonce for every attempt.
- First verify an actual EIP-191 or EIP-1271 wallet signature over the exact unmodified challenge, including address, approved chain and host. This repository does **not yet integrate an audited EVM signature verifier**, so wallet login routes must stay disabled.
- After genuine signature verification, use the service-role-only `certifiks_redeem_wallet_nonce` RPC to atomically consume exactly that hashed nonce/message/address/chain. An expired or already consumed nonce must reject.
- Only then create a new opaque session in the protected database, storing the SHA-256 digest of the 256-bit session token and a separate CSRF digest. Store the opaque token in a Secure HttpOnly __Host- cookie, never localStorage. On successful sign-in, rotate credentials; on logout, revoke tokens before clearing cookies.
- GitHub account linking requires verified OAuth consent from the *same authenticated user* and installation identity revalidation. The current GitHub App snapshot code **does not provide this consent flow**.
- A role list on a client request or a forged organization ID confers no privileges. Trusted role membership must be loaded server-side from the migration tables and checked against each bounty's ownership and mutually exclusive verifier governance roles.
- Private artifact authorization is blocked until the above is wired into protected HTTP handlers and tests.

## Migration

`supabase/migrations/202610260001_wallet_auth_foundation.sql` creates RLS-enabled server-only users/wallets/GitHub identities, atomic challenge redemption, session persistence/rotation fields and organization role memberships. This migration has not been executed against a real deployment and should not be considered deployed.

## Outstanding P0 acceptance

A real wallet signing adapter (correct chain-domain binding, EIP-1271 smart contract wallets, replay-resistant Ethereum signature verification), independently verified GitHub OAuth account ownership, secure session endpoints and revocation, server-side role-policy enforcement, actual restricted API routes, real multi-device signout/wallet switching, IDOR tests and live deployment are still required.

Do not close #23 merely because the challenge/session cryptographic primitives pass tests.
