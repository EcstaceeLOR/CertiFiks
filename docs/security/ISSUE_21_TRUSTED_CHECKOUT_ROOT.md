# Issue #21 — Trusted checkout boundary and conservative container exits

**Scope:** a fail-closed security increment for the existing local Docker sandbox. It is **not** a penetration test, independent sandbox audit, live hostile-workload deployment, or approval to execute arbitrary public repository code.

## Host filesystem trust

The worker now requires the operator-owned environment variable `CERTIFIKS_TRUSTED_CHECKOUT_ROOT` to name a dedicated **absolute** directory containing clean, pre-vetted checkouts. If this setting is absent, relative, the filesystem root or points at an unavailable directory, execution fails. The realpath of the chosen workspace must be a **strict child** of that configured root. Root itself, parent directories, unrelated sensitive host locations and symlink escapes are refused before Docker starts; the validated canonical path is the only source used for the read-only bind mount.

Example for an operator-managed, private sandbox worker (NOT a public-ready deployment):

```sh
install -d -m 0700 /var/lib/certifiks/verifier-checkouts
export CERTIFIKS_TRUSTED_CHECKOUT_ROOT=/var/lib/certifiks/verifier-checkouts
```

Only an authenticated server worker should construct and populate the per-job checkout, in a directory inaccessible to untrusted host users. Do not set the trusted root to `/`, `/home`, `/tmp`, an applications secrets directory, the primary API working directory, or a shared public workspace. The root alone is not a tenant/job authorization check; the scheduler must separately assert the requested job's ownership.

## Resource and evidence boundaries

The Docker policy already disabled networking, used read-only checkout mounts, dropped Linux capabilities, prevented privilege escalation, limited process count/memory/CPU/file sizes, and provided a bounded temporary filesystem. It now additionally denies core dumps, limits user processes, disables host-side container log storage, and separates IPC. The program explicitly treats Docker invocation failures (exit 125–127) and likely killed/OOM exits (137/143) as `runner_error`, *not* a valid acceptance-test failure that could satisfy the bug's expected-failure proof.

Node tests use temporary directories and symlink escapes without requiring a Docker daemon. This is regression evidence for the boundary checks, not evidence of container namespace isolation or a completed baseline/candidate run.

## Remaining Issue #21 acceptance

- Audit the runtime and Docker daemon configuration under an **unprivileged rootless service** or an independently reviewed microVM/container platform. Validate seccomp, user namespace, device isolation, metadata access, mount permissions and host-escape behavior.
- Add immutable job-specific directory ownership checks, strict artifact-size/output streaming, forced cleanup/termination after timeouts, rate limits, resource exhaustion tests, and tested controls for fork bombs, malicious dependencies, archive extraction, and oversized artifacts.
- Prove both baseline and candidate checkouts are independently fetched and immutable, and that clean workers don't reuse state or credentials between jobs.
- Execute hostile isolation fixtures on a dedicated sandbox host and obtain an independent security review. No production untrusted fork execution is authorized by passing CI alone.

**Issue #21 stays OPEN** until independent isolation penetration tests, live execution transcripts and service/operations approval exist.
