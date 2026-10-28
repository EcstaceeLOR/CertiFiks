# Issue #20 — GitHub App least-privilege, PR repository identity

**Status: security-hardening increment only. No live GitHub App installation, consent, real webhook, verified bug fix or third-party GitHub evidence has been completed by these synthetic tests.**

## Narrow installation tokens

`apps/api/src/github/app-auth.ts` already requests a token for **one numeric repository ID** with **read** permissions for contents and pull requests and denies untrusted repo scope. This update additionally **refuses** a response claiming `write` authority where only `read` was requested. Any elevated-permission response is treated as a **FORBIDDEN** app-authentication failure, rather than silently accepting extra privilege. The token stays server-side and is never written to audit evidence.

## Signed webhook repository cross-check

The webhook signature is computed over the raw bytes and remains checked before parsing. For `pull_request`, the parser now requires the numeric `pull_request.base.repo.id` to match the top-level `repository.id`, a canonical pinned 40-character lowercase base SHA and head SHA, and (except when a closed PR has a deleted fork) the source `pull_request.head.repo.id`. This prevents a validly signed but malformed/inconsistent event from supplying contradictory repository identities downstream. The fix **does not** trust the webhook alone as a developer fix or use the raw PR body as code authority.

CI tests sign mock payloads with a synthetic HMAC and confirm that wrong base-repository identity, missing source ID and malformed base SHA are refused with HTTP 422 before durable journal insertion; additionally, a test token with `write` contents or PR permissions cannot satisfy the narrowly scoped App contract.

## Remaining Issue #20 acceptance

- Register a real GitHub App in a controlled developer/maintainer-owned GitHub organization, install it with human consent and bound repository selection, and use a secure server-side installation/session configuration. Never provide a personal access token or private signing key to a chat.
- Demonstrate signed live `installation`, `installation_repositories` and `pull_request` delivery. Archive redacted HTTP/DB acknowledgements, prove duplicate and out-of-order replay handling and confirm the PR head after force-push, transfers and uninstallation.
- Ensure the durable revocation processing/worker queue rejects work after access loss, including app token expiry and rate limits. Independently check entitlement and on-chain state before changing anything payable.
- Conduct cross-tenant IDOR and webhook replay/secret-recovery review, with authorized external installation and participant evidence.

Issue #20 stays **OPEN** until those live acceptance criteria are met. Neither source passing CI nor a generated webhook fixture constitutes a connected customer repository.
