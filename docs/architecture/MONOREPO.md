# Architecture baseline — Issue #4

The repository begins with **four separately buildable workspaces** and one independent contract reference. These are foundations, **not a finished product**.

| Area | Purpose | Maturity |
|---|---|---|
| apps/web | Next.js 16 app with truthful pre-launch state | Scaffold only; no bounty actions |
| apps/api | Fastify HTTP process with real /health transport endpoint | Service scaffold only; no data persistence |
| workers/verifier | Closed-by-default Node worker interface | Explicitly refuses to run untrusted code until #21 |
| packages/shared | Shared version, types and contracts for runtime APIs | Schema drafts only; canonical hashes in #19 |
| contracts | Historical EVM escrow starter, initially unreviewed | Not for real funds; #6 builds/tests/fixes |
| research/reference-model | Historical deterministic Python behavioral model | Known unsafe timeout semantics, not the final contract |
| docs/product, docs/security | PRD, lifecycle, decision gates, threat model | Specification, not deployment evidence |

**Trust architecture:** Wallet + GitHub App → authenticated API/database → sandboxed verifier worker → signed review → custody contract → indexer/API/UI. Every boundary is unimplemented until its ticket accepts actual proof. No platform service is authorized to hold sponsor wallet private keys or mark a bounty paid without a real contract receipt.

**Portaldot chain gate:** #2 concluded a reproducible no-go for V3 deployment (legacy mainnet alone is insufficient). #18 requires real qualifying V3 runtime and signed deployment + read/write evidence. Solidity remains reference until that gate is cleared; do not claim native Portaldot deployment.
