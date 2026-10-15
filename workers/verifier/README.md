# CertiFiks verifier runner (Issue #21)

The runner delegates untrusted tests to a pre-provisioned Docker runtime. It is intentionally **not** an internet-facing job API. Callers must obtain an immutable, trusted checkout and a pre-approved test image digest from the trusted control plane.

## Isolation defaults

- Docker image must use `repository@sha256:<digest>`; tags are rejected.
- `--network=none`, read-only root filesystem, read-only workspace mount, non-root UID, all Linux capabilities dropped, no-new-privileges, PID/CPU/memory/file-size/open-file limits, and bounded timeout/output.
- Only a minimal PATH is passed to the Docker CLI process; application environment secrets are not forwarded.
- No Docker socket, host home, cloud metadata, GitHub token, or production credential is mounted or injected.
- Shell entrypoints are rejected; command and arguments are passed as distinct argv entries, never through a shell.
- Result metadata includes status, exit code, duration and a SHA-256 digest over the recorded result.

## Operational prerequisites

Provision Docker on a dedicated ephemeral worker host with rootless Docker or equivalent hardened runtime, seccomp/AppArmor/SELinux policy, outbound egress blocked at the host/network layer, no cloud instance credentials, and an unprivileged service account. Pull and verify approved images out-of-band; the runner uses `--pull=never`. Destroy worker VMs between trust boundaries where possible.

## Limits and non-claims

Container flags are defense-in-depth, not a complete VM boundary. Do not execute public untrusted workloads until an independent security review, host-level isolation testing, and a disposable worker deployment are complete. This module does not implement the durable queue/retry lifecycle tracked in #28, image signing policy, a control-plane API, or production worker provisioning. It fails closed when Docker is unavailable and does not manufacture successful verdicts.
