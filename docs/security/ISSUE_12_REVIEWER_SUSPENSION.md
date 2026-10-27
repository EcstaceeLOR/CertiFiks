# Issue #12 — Emergency verifier organization suspension

The reviewer registry has an additional governance-only emergency suspension path. This is contract code, not a social promise or approval for live funds.

`suspendReviewerOrganization(orgId)` immediately sets the registered organization inactive and suspended. The current signer and controller cannot accept a review, declare new report evidence, rotate keys or obtain new assignments while suspended. An unapproved signing-key rotation proposal is discarded to prevent a queued key from becoming active silently.

`clearReviewerSuspension(orgId)` requires the original governance account. It only clears the suspended status; **a separate explicit transaction by the organization's enrolled controller is required to reactivate**. Old accepted jobs and previously declared report digests remain in storage. The signer epoch does not advance simply because an organization was paused, so any signer key compromise still requires an independently approved key rotation or permanent revocation. A permanently revoked organization cannot be suspended, un-suspended or reactivated.

Foundry tests cover signer refusal during suspension, controller's inability to bypass a governance hold, third-party attempts to lift a hold, two-party reactivation, permanently revoked organizations, preservation of accepted evidence and conservation of the contract balance.

**Trust boundaries and release limits:** Governance can censor or delay reviewers by imposing holds. Suspension therefore needs an independently adjudicable incident response and funding-safe reviewer fallback in Issues #14–#15; it is not itself a secure timeout resolution. Even two organization IDs do not prove distinct economic beneficiaries. Identity enrollment and independence require actual external vetting, real participants, ongoing monitoring and a production security review before Issue #12 can be closed. No test harness is a qualifying Portaldot deployment or real-money escrow.
