# Issue #29 — Consent-first durable notification identities

**Status:** persisted notification/inbox schema and SQL regression checks, NOT operational multi-channel delivery.

Migration `202610260006_notification_delivery.sql` extends the pre-existing notification table with an immutable event-idempotency digest, tenant-scoped bounty target and read timestamp. It creates a user/organization preference row (in-app on, email off by default) and a private delivery-outbox record with explicit `queued`, `delivering`, `delivered`, `retry`, `blocked` and `cancelled` statuses.

The server-only `certifiks_enqueue_notification` procedure checks recipient membership and tenant-scoped bounty reference, hashes the logical event once per recipient, handles repeated webhook delivery idempotently, rejects event collisions with altered content and honors in-app opt-out. The service-only `certifiks_mark_notification_read` requires both the organization and recipient ID; the API must derive both from an independently authenticated session, **never from a user-controlled path or header**.

**No emails or GitHub Check Runs are dispatched by this migration.** An `email_opt_in=true` flag alone does not prove that a delivery address is verified, a provider is configured, or a message has been sent. No provider receipts are fabricated. The database and all private notifications/outbox rows deny direct anon/authenticated browser access.

## Reproduce

CI applies all migrations and runs PostgreSQL tests for event deduplication, collision rejection, opt-in, tenant separation, read ownership and private RLS. Run `npm ci && npm run test` for existing Node and API checks.

## Still required for full Issue #29

- Finish production session/GitHub/wallet identity and role enforcement (Issue #23), implement actual secured inbox list/read APIs, authorized click routing and visible preferences.
- Configure and test an approved email provider using a verified destination address, explicit consent, unsubscribe for noncritical mail, idempotency headers, per-event rate budgets and provider receipt reconciliation.
- Implement GitHub App scoped Check Run/PR status updates with appropriate installation permissions, a real durable sending worker, bounded retries, lease fencing, dead-letter review and API/UI failure transparency.
- Deploy database migrations and show captured redacted notifications from real independent participants on a completed bounty.

Keep Issue #29 **OPEN**. This migration does not claim user-visible email, GitHub notifications, or production product readiness.
