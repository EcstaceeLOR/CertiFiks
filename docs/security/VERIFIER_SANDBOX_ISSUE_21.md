# Issue #21 — Isolated verifier runner

## Threat model
Contributor-controlled repositories, build scripts, package lifecycle hooks, tests, and dependencies are hostile. The verifier worker must assume arbitrary code execution inside the workload and must not hold secrets or trust mutable artifacts.

## Implemented runner controls
- Digest-pinned image only; image pull is disabled during execution.
- Docker network disabled, read-only root and checkout, non-root user, capabilities dropped, no-new-privileges, PID, memory, CPU, file-size, open-file and wall-clock bounds.
- No environment pass-through except a minimal PATH for the host Docker CLI; no secret, socket or host-home mounts.
- Shell command entrypoints rejected; stdout/stderr are capped and result metadata is hashed.
- Invalid image, command and timeout requests fail before Docker starts.

## Required release gates still outstanding
This implementation is a hardened execution adapter, not proof that the production host is safe. Before public workload enablement:
1. Run the worker on disposable, credential-free VMs with rootless Docker or a stronger microVM runtime.
2. Enforce host/network egress denial and metadata-service blocking outside the container.
3. Add signed image provenance and immutable artifact intake from the trusted control plane.
4. Run adversarial tests for fork bombs, filesystem escape, oversized artifacts, dependency attacks, and cross-job contamination.
5. Obtain independent security review and attach actual logs.
6. Integrate the durable queue and retry/dead-letter lifecycle under Issue #28.
No production deployment or independent review is claimed by this document.
