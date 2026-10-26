# Issue #25 — Deterministic before/after fix qualification

**Status:** real orchestration logic + mocked executor regression tests, NOT actual verified fix execution or payout eligibility.

`workers/verifier/src/qualification.ts` orchestrates an immutable baseline and candidate head through the same digest-pinned, network-disabled container image and the same acceptance command. It:

1. Validates canonical distinct base/head SHAs, funded plan/manifest digests, digest-pinned image and separate trusted acceptance/regression commands.
2. Fails closed **before any execution** if the trusted acceptance-test source digest differs between the independently pinned baseline and candidate or does not match the committed test plan.
3. Runs the baseline acceptance suite twice, requiring a nonzero exit with the exact committed failure digest in both runs. A baseline that already passes, fails with a different reason, or gives variable output is not an accepted fix.
4. Runs the same committed acceptance suite against the candidate twice, requiring two clean passes and identical observable result digests.
5. Runs a separate committed regression suite against the candidate twice, requiring two clean and repeatable passes.
6. Emits a structured status: qualified (claim only), rejected, needs_review (flaky), inconclusive (ambiguous/timeouts) or infrastructure_error. Only public digests and status are returned; raw stdout/stderr are not returned in the public qualification receipt.
7. Marks every result `signed:false` and `payoutAuthorized:false`. Trustworthy settlement requires Issue #22 enrolled independent signatures, private evidence retention and on-chain decision state.

Run local unit tests with `npm run test --workspace=@certifiks/verifier`.

This implementation does not clone a real PR, prove a real baseline's bug was fixed, independently authenticate a test-source checksum, detect adversarial changes to hidden dependencies or sign the decision. A trusted backend must fetch exact GitHub revisions under Issue #20 installation-scoped tokens, retain hidden sponsor tests outside the developer workspace, independently compute the test directory/file commitment, and save full runner receipts in Issue #22 protected evidence storage.

The next acceptance gate is a **real, reproducible GitHub bug-fix trace**, with independent reviewer/verifier signatures and a documented third-party reproduction. Until that evidence exists, **Issue #25 remains open**.
