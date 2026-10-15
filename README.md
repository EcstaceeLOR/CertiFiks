# CertiFiks

**Prove the Fix. Release the Reward.**

CertiFiks is building a secure software-repair bounty protocol: a maintainer funds a fixed acceptance policy, a contributor submits an immutable GitHub revision, independent eligible reviewers verify meaningful before/after tests, and the agreed on-chain contract releases a reward only after the challenge window.

## Current status (October 15, 2026)

**Pre-release engineering. No working bounty marketplace, real verification pipeline, live escrow, Portaldot V3 deployment, paid reward or production security audit exists yet. Do not send real tokens to any claimed CertiFiks contract.**

Issue #2 captured a reachable, legacy Portaldot Mainnet RPC and documented a **NO-GO** on unverified V3 testnet deployment. Issue #18 remains an on-chain release blocker. The historical Solidity starter and Python model are retained explicitly as **unsafe research references**: they contain flawed timeout/refund semantics. A green baseline smoke test cannot make them safe.

## Workspace map

| Path | Purpose | Readiness |
|---|---|---|
| apps/web | Next.js/React interface with accurate pre-launch status | Builds; no bounties |
| apps/api | Fastify API transport and real /health endpoint | Runs; no product endpoints |
| workers/verifier | Protected verifier boundary | Explicitly disabled until #21 |
| packages/shared | TypeScript constants / early shared types | Foundation only |
| contracts | Solidity historical EVM escrow and Foundry smoke test | Unreviewed, unsafe, not deployed |
| research/reference-model | 14 Python characterization tests for historical model | Known timeout vulnerability |
| docs/product | Requirements, lifecycle, acceptance criteria | Design |
| docs/security | STRIDE threat analysis, invariants and adversarial test matrix | Design |
| docs/hackathon | Portaldot V3 feasibility decision and observed network probes | Blocked for deployment |

## Reproducible local setup

Prerequisites: Node.js 22+, npm 10+, Python 3.12+ for reference-model tests, Foundry for EVM reference compilation. No API keys are required for the local transport and static checks.

1. Clone the repository and run npm ci from root. The committed package-lock.json pins the installed dependency graph.
2. Run npm run lint, npx biome ci ., npm run typecheck, npm run test, npm run build.
3. Run python3 -m unittest discover -s research/reference-model -p 'test_*.py' -v to execute the **historical**, knowingly unsafe Python baseline tests.
4. Run cd contracts && forge build && forge test for an EVM syntax/constructor smoke check only. This is not security proof or actual Portaldot V3 compatibility.
5. Run npm run dev --workspace=@certifiks/api (listens on localhost:3001) or npm run dev --workspace=@certifiks/web (localhost:3000).

Environment variable names, **without secrets**, are documented in .env.example. Never commit .env files, wallet seeds or GitHub installation tokens.

## Security and review

- Every code change links an acceptance-test-bearing issue and a reviewed PR, with reproducible negative cases where applicable.
- Privileged services cannot infer payout success from a frontend display or off-chain CI result.
- Untrusted PR code must not execute on the API/CI host or be provided secrets. The initial verifier explicitly fails closed.
- Contract release requires a proper role-separated review, enforceable dispute liveness, accounting invariants and an external audit before mainnet money.
- Foundational specifications: [product charter](docs/product/PRD.md), [security threat model](docs/security/THREAT_MODEL.md) and [repo architecture](docs/architecture/MONOREPO.md).
- Canonical [issue backlog](https://github.com/EcstaceeLOR/CertiFiks/issues/1) and [V3 compatibility evidence](docs/hackathon/network.md).

The brand name CertiFiks remains provisional pending formal trademark review.
