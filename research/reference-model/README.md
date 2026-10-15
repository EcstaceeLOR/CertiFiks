# Historical ProofPatch reference model

Provenance: extracted/reformatted from the starter archive named ProofPatch_Starter_2026-10-15.zip and preserved during CertiFiks Issue #4. The prior 14 Python unit tests are here to characterize pre-existing behavior only; they do **not** establish contract security or a qualifying Portaldot deployment.

**Critical historical flaw retained for reproduction:** a sponsor can reclaim escrow when verification times out even though a contributor submitted work before deadline. The characterization test passes because the model captures this unsafe behavior. It is explicitly prohibited by the new security requirements in #3 and must be fixed and regression-tested in #6/#14/#15.

Run: python3 -m unittest discover -s research/reference-model -p 'test_*.py' -v

Future protocol contracts must not blindly copy this reference model. The canonical product specification lives at docs/product/PRD.md.
