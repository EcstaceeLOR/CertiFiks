# Issue #32 — Sponsor funding preparation without fabricated escrow deposits

This milestone implements **private immutable funding preparations only**, not a deployed live bounty funding flow.

The migration `202610260008_sponsor_funding_intents.sql` introduces sponsor- and tenant-bound intents whose acceptance manifest hash, chain ID, atomic reward amount, bounty ID and sponsor cannot be changed after preparation. Only the backend service role can execute `certifiks_prepare_sponsor_funding` and `certifiks_cancel_sponsor_funding`. The database checks the sponsor is the actual bounty sponsor and that its exact still-unfunded draft financial terms match. Repeated idempotency hashes return the existing intent rather than create duplicate financial instructions. One active prepared intent is permitted per bounty and a protected trigger freezes the corresponding bounty reward/manifest until cancellation. All prepare and cancel transitions emit immutable audit entries.

**No approval or money movement:** an intent state is strictly `prepared` or `cancelled`. No wallet signature, chain transaction, escrow balance, funded listing or payout claim can originate from this feature. The TypeScript `ServerSponsorFundingIntentV1` returns `walletSigned:false`, `fundingConfirmed:false` and `payoutAuthorized:false` and is usable only inside an independently authenticated, privileged backend process. Never expose the service key in the browser or connect a public endpoint that accepts arbitrary caller-supplied principals.

## Reproduction

CI applies this SQL migration to PostgreSQL, asserts sponsor-only preparation, safe idempotent retries, funding term locks, unchanged on-chain records, immutable event retention, cancellation and private access. The API unit suite covers strict canonical decimal-string values and no fake funding on upstream failure. The database backup/restore check includes the additional unfunded draft bounty.

## Incomplete production gates

- Obtain a **real approved Portaldot runtime and contract deployment**. Confirm whether wallet/EVM APIs can actually fund escrow. Issue #18 remains open.
- Complete verified sponsor wallet/GitHub login and private owner authorization (Issue #23), GitHub installation (Issue #20) and live bounty creation/repository selection APIs (Issue #26). Only then expose a writable sponsor workspace.
- Add explicit browser wallet consent, transaction simulation, safe allowance mechanics and chain-specific fee confirmation. Capture actual tx hashes after the wallet signs; never automatically sign on behalf of the user.
- Validate the signed transaction on the correct chain, verify contract ABI and event amount/manifest, wait for independent finality and reconcile funds before marking the bounty funded or publishing it. Real refunds, dispute and assignment paths require their own E2E checks.

Keep Issue #32 **OPEN** until new sponsors can successfully fund verified testnet escrow end to end. This PR cannot complete the entire feature or establish production readiness.
