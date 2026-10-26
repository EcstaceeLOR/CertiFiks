# Issue #28 — Durable verification orchestration substrate

**Status: database/worker transport integration only; not live verification or payment authorization.**

The PostgreSQL migration `supabase/migrations/202610260005_verification_jobs.sql` creates one idempotent job per tenant, bounty, GitHub attempt, funded manifest digest and stage. Allowed stages are `checkout`, `baseline`, `candidate`, `regression`, `review`, `synchronize` and `notify`. The service-only enqueue procedure verifies that the attempt belongs to the exact tenant/bounty and committed funded manifest. Duplicate webhooks cannot enqueue multiple work items for the same stage.

Service-only workers claim jobs using `FOR UPDATE SKIP LOCKED`, receive a fresh random lease UUID and incremented attempt counter, and must present both to heartbeat or finish a job. Recovered leases are fenced by attempt ID so a crashed worker cannot acknowledge the next worker's attempt. Retries use bounded exponential backoff; the database records terminal `dead_letter`, `cancelled` and `succeeded` states. Browser roles cannot read or write the queue. The `ServerVerificationQueueV1` adapter lives in `workers/verifier/src/job-queue.ts`, deliberately *outside untrusted Docker containers*.

For local reproduction:

```sh
npm ci
npm run test --workspace=@certifiks/verifier
```

CI applies all SQL migrations on PostgreSQL 16, exercises duplicate enqueue, cross-tenant rejection, wrong-lease acknowledgement, retry backoff, re-leasing, dead-letter transitions, and verifies that queue operations do not create payment rows. CI also re-tests the complete database backup/restore.

## Release blockers (do not close Issue #28 yet)

- Connect an actual long-running credential-free verifier executor to checked-out source code and test stages with persisted immutable evidence, source pinning and signed reports.
- Add job authorization and audited operator-only replay controls, cancellation propagation to already-started containers and out-of-band worker heartbeats/metrics. Backend service-role access by itself does NOT authenticate an operator.
- Fault-inject real container/process termination and network outages against a deployed shared database and multiple workers; prove no duplicate signatures, no lost runs, no cross-tenant reads and no duplicated settlement.
- Define end-to-end stage-to-stage transition proof including exact baseline failure fingerprint, candidate test pass, regressions, verifier independence and escrow-specific payment idempotency. Nothing here invokes a payout.
- Provision real Supabase credentials and migrate an approved environment. Never expose service-role keys, private artifacts or wallet signing keys in runner containers.

This foundation must not report a fix as verified merely because a job was enqueued or marked `succeeded`. No simulated success or fabricated production readiness.
