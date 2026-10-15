# Issue #20: GitHub signed webhook ingress (partial delivery)

This change introduces a real HTTP POST /webhooks/github endpoint. It verifies GitHub's X-Hub-Signature-256 over the exact received request bytes using a configured secret and constant-time comparison; admits a strict subset of installation, installation_repositories and pull_request event types; validates numeric installation/repository/PR identities; and records a minimal delivery journal using exclusive-create files for duplicate suppression.

## Configuration
- GITHUB_WEBHOOK_SECRET: the genuine GitHub App webhook secret, minimum 32 characters.
- WEBHOOK_JOURNAL_DIR: an **absolute directory on a durable persistent shared volume**, writable by the API process and not publicly served.
- For GitHub App settings, target the HTTPS URL /webhooks/github, choose installation, installation_repositories and pull_request subscriptions, and grant only the required repository Content and Pull requests read permissions.

Never send test-only tokens or webhook secrets to browsers, untrusted fork builds, or public logging. File-based O_EXCL idempotency works for one API with shared durable disk. It is NOT sufficient for distributed serverless replicas or a multi-instance production event queue. In those environments, fail closed until a transactional database and retryable durable queue are connected. The endpoint returns HTTP 503 if secret or journal directory is absent, HTTP 401 on invalid signature, HTTP 422 on unsupported types, 202 when newly recorded, and 200 for duplicates. A crash before durable storage must not be acknowledged as successful.

## Critical incomplete acceptance gates
- Register a real GitHub App and complete signed setup, installation authorization, scoped user consent and private repository selection (needs actual credentials and deployment).
- Authenticate live installation-scoped REST API access, app JWT/token expiry and renewal and bind installation/repository IDs to the logged-in wallet user.
- Create a durable repository access state machine and replayable ordered worker queue; handle force pushes, closed PRs, permission loss, installation revocation and rate limits before ever issuing a verified-fix outcome.
- Test on a real GitHub App installation with redacted delivery receipts and real PR/reinstallation/permission-revocation walkthrough.

This PR intentionally does NOT pretend to prove a fixed bug, install an app, process PR contents, execute runner jobs or authorize payouts. Issue #20 must stay OPEN until these are implemented and checked end-to-end.
