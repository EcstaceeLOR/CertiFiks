# CertiFiks EVM contract baseline — SECURITY WARNING

This Solidity contract is adapted from the ProofPatch research starter. It is **not audited, not production-safe, not deployed on Portaldot V3 and must not accept real funds**.

Known confirmed **design defects** of the imported starter (not repaired in issue #4):
- Timely submitted work may be forfeited when an external reviewer misses a deadline.
- Pushing native currency to a reverting developer contract can block a valid payout.
- Arbitrator failure can indefinitely freeze disputed funds.
- Separate signer wallets are not equivalent to independent legal verifier organizations.
- Acceptance test evidence is represented only by an opaque hash, with no real GitHub authorization or isolated runner.

See [security model](../docs/security/THREAT_MODEL.md) and future remediation issues #6 and #9–#17. The Foundry build/smoke test in this repository establishes only that source *compiles*, not that it is secure. No deployment scripts or live transaction claims are included.

Run from the repository root: cd contracts && forge build && forge test
