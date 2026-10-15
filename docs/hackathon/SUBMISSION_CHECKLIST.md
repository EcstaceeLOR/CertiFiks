# CertiFiks — Portaldot Hacker House 2026 eligibility and submission checklist

**Issue:** #8 · **Reviewed:** 2026-10-15 · **Owner:** Solo founder / builder · **Status:** TRACKER READY; **SUBMISSION NOT READY / NOT SUBMITTED**. The official DoraHacks per-project submission UI is currently inaccessible to unauthenticated public web retrieval, so final field-by-field validation is outstanding.

> This file is an evidence-driven tracker, not an assertion that a project check-in or final submission has happened.

## 1. Sources and confidence

| Source | Tier | Confirmed or limited scope |
|---|---|---|
| [DoraHacks organizer Eventbrite listing](https://www.eventbrite.com/e/portaldot-hacker-house-2026-tickets-2002321816454) | Organizer-issued primary event announcement | Dates Oct 14–Nov 6; Portaldot V3.0 EVM/WASM compatibility; individual builders permitted; linked application portal |
| [Official DoraHacks event registration page](https://dorahacks.io/hackathon/2362/detail) | Submission portal / authority of record | Must confirm detailed rules and fields while authenticated; anonymous fetch unavailable or 405 |
| [HackathonRadar event reproduction](https://www.hackathonradar.com/database/hackathon/portaldot-hacker-house-2026) | **Secondary** copy of purported rules | Provides detailed exact UTC+8 times, check-in fields, scoring weights, code compliance and prize arrangement; independently recheck with organizer |
| [Portaldot Discord](https://discord.gg/portaldot) | Event's published official support channel | Confirm RPC, testnet, nationality/payout, check-in/form and time discrepancies with organizer |
| [GitHub issue #2 network decision](./network.md) | First-party CertiFiks engineering evidence (not event rules) | Public legacy RPC proof and NO-GO for V3 integration until authentic deployment exists |
| [Submitted evidence ledger](./SUBMISSION_EVIDENCE.json) | Project-controlled machine-readable self-report | Statuses enforced by CI; VERIFIED entries need actual evidence URLs, never mock data |

**Important distinction:** Public event pages say V3 supports both EVM and WASM, but our successful read-only probe is of **documented legacy Portaldot Mainnet**, which does not implement eth_chainId on that endpoint. Neither facts nor marketing alone is proof of compatible V3 **testnet** deployment.

## 2. Key dates in Nigerian time (WAT, UTC+1)

Time-of-day details below are **reported by secondary event reproduction**; compare against live DoraHacks countdown before submission.

| Event | Reported UTC+8 | Converted WAT (UTC+1) | State |
|---|---|---|---|
| Kick-off workshop | Oct 14, 20:00–22:00 | Oct 14, 13:00–15:00 | Past |
| Check-in deadline | **Oct 24, 20:00** | **Sat Oct 24, 13:00** | **HIGH PRIORITY** |
| Feedback results | Oct 26, 24:00 (ambiguous calendar-day notation) | Oct 26, 17:00 if it means start of Oct 27 in UTC+8; verify | Unconfirmed |
| Office-hours application deadline | Oct 30, 20:00 | Oct 30, 13:00 | Optional event |
| Office hours | Oct 31–Nov 1, 14:00–18:00 | Oct 31–Nov 1, 07:00–11:00 | Optional |
| **Final code freeze and submission** | **Nov 6, 12:00** | **Fri Nov 6, 05:00** | **HARD DEADLINE** |
| Live demos | Nov 7–8 | Exact slots TBA | Await organizer |
| Community voting | Nov 9 local event calendar day | Opening expected Nov 8, 17:00 WAT; verify | Conditional |
| Winners | Nov 10 | Exact time TBA | Unknown |
| Claimed reward distribution | Nov 13, 20:00 | Nov 13, 13:00 | Unverified payment conditions |

**Build-period discrepancy:** A community announcement refers to Oct 13 16:00 UTC, while detailed competition text refers to Oct 14–Nov 6. Historical ProofPatch starter is pre-existing research; explicitly distinguish it from genuine new CertiFiks code, and verify eligibility of reused starter with organizer. Keep repo commits/PRs readable and do not disguise provenance.

### Internal delivery gates (not organizer rules)
- **Before Oct 22 WAT:** aim to secure the qualifying testnet path, one genuine transaction, verifiable committed GitHub fix and initial recorded core flow, or identify irrecoverable blocker for honest go/no-go. This is a founder planning target, not organizer deadline.
- **By Oct 23 WAT:** freeze a reviewable check-in evidence package, ideally leaving a day to correct a portal issue. Never present a fictional core demo.
- **Before Nov 4 WAT:** target final demo/video, contract receipts and runnable instructions before the last 24 hours. Requirement that core final versions not be first committed in last 24h is reproduced secondary event rule.

## 3. Eligibility, solo participation and track strategy

- **Single developer/founder:** Organizer event description explicitly welcomes individuals with independent Web3 product development capacity. No teammate must be recruited to develop CertiFiks.
- **Nigeria:** Public sources reviewed contain **no explicit Nigeria exclusion**, but this is **NOT clearance** for residence/citizenship or prize payment. Must verify eligibility, USDT/POT payout route, any KYC and tax requirements directly with organizer; do not provide sensitive documents in public repo.
- **Official tracks (as reproduced):** Modular Cloud & Middleware; Multi-Chain & Cross-Chain Infra; Node Operations & Tooling; Ecosystem DApps.
- **Recommended primary category:** **Modular Cloud & Middleware** if verified middleware APIs and reproducible evidence are actually operational. **Backup:** Ecosystem DApps if the on-chain escrow/bug-fix marketplace is the strongest executed contribution. Selection is provisional until the exact DoraHacks application options are viewed.
- **Independent main innovation:** agreed tests fail on baseline and pass on exact patch, with signed independent reviewers and fair challenge before non-custodial reward withdrawal. This is a future feature until real tests/escrow are implemented; don't claim that existing bounty marketplaces never support escrow.

## 4. Detailed submission rules and evidence map

| Requirement (third-party reproduction unless otherwise noted) | Evidence expected | Actual CertiFiks status | Owner / next |
|---|---|---|---|
| Public GitHub source and continuous commits | [GitHub repo](https://github.com/EcstaceeLOR/CertiFiks), [main commits](https://github.com/EcstaceeLOR/CertiFiks/commits/main/) | **YES:** 7 observed post-Oct14 main commits at review, PR history exists | Maintain issue #45 |
| At least 3 substantive commits during build | Staggered original commits/PRs; no code-drop at final hours | **YES count;** confirm organizer accepts starter provenance | #8/#45 |
| Complete README, reproducible build instructions | [README](../../README.md) and existing CI logs | **FOUNDATION ONLY**; not runnable end-to-end product | #40/#45 |
| Product architecture diagram | [Competition architecture](../architecture/COMPETITION_ARCHITECTURE.md) | **Diagram documented**, explicitly planned/unimplemented | #8 |
| Current progress and outstanding features | [Roadmap issue #1](https://github.com/EcstaceeLOR/CertiFiks/issues/1), [evidence ledger](./SUBMISSION_EVIDENCE.json) | **Available**; clear unfinished states | #8 |
| Qualifying Portaldot V3 **testnet** deployment | Authenticated network ID and testnet RPC, actual deploy/read/write receipt | **BLOCKED**: only legacy mainnet read-only probe succeeded | #18 |
| Contract address and transaction hash | Live verified block, contract ID and explorer | **MISSING**; do not invent placeholder | #18 |
| At least one *working* core function at check-in | Accessible live working demo **or** ≤3-minute real flow video | **MISSING**; pre-launch page cannot qualify as functional demo | #20/#25/#32/#40/#45 |
| Final runnable code + installation/deployment guidance | Actual build, env template, smoke test commands and service endpoints | **PARTIAL:** workspaces build; no end-to-end product | #40/#45 |
| Final video (max 3 min), real product, Portaldot usage | Public video and same tx/commit evidence | **MISSING** | #45 |
| Final pitch deck | PDF or public deck, why Portaldot, user pain, proof, future roadmap | **MISSING** | #45 |
| Nigeria entry and prize-payment arrangements | Organizer's written confirmation | **UNKNOWN** | #8 |
| Submission receipt | DoraHacks link/screenshot confirming official check-in and final | **NOT SUBMITTED** | #45 |

**Important:** The original event reproduction allows simulated data in a check-in video, but that is *not* equivalent to genuine working core product. Our stricter founder acceptance policy prohibits passing off mock interactions as live escrow or independent verification.

## 5. Judging scorecard (secondary report; reverify in DoraHacks)

| Category | Weight | What we can responsibly prove today | Biggest gaps |
|---|---:|---|---|
| Technical feasibility | 30% | Reproducible CI, compiled historical reference, 16 Foundry behavior tests, shared domain hashes, threat model | Qualifying deployed V3 contract, safe custody, real GitHub event verification, full E2E |
| Innovation | 30% | Defined a narrower verifiable-fix payment protocol than merge-only rewards, tests/hashes specified | Need execute and show meaningful before/after proof and differentiate against existing bounties |
| Ecosystem contribution | 20% | Public technical docs and source; compatible chain plan contingent on V3 | Demonstrable actual Portaldot network transactions, ecosystem adoption |
| Business potential | 20% | Clear sponsor/developer personas, competitive hypothesis, no fabricated pilots | Real external interviews/consent (#7) and measured costs (#46) |

Judging only confirmed if source-of-truth DoraHacks page or organizer affirm weights; do not quote above as officially final until verified.

### Presenter narrative (not yet a claim)
- **Problem:** A merged PR can fail to repair its target defect; paying on merge alone may leave sponsors exposed and contributors facing ambiguous reviews.
- **Approach:** Fix terms committed before funding; trusted baseline-fails/patched-passes test evidence; independent accountable reviewer signoff; bounded dispute; on-chain credit/withdrawal.
- **What Portaldot adds:** Actual qualifying smart-contract custody and public settlement, if V3 path is verified. Without deployment we cannot claim chain contribution.
- **Business:** Need proof maintainers accept verification latency/cost and contributors prefer protected payments; interviews currently uncompleted.

## 6. Check-in packet template — fill only with real artifacts

- Project name: CertiFiks
- Tagline: Prove the Fix. Release the Reward.
- Solo founder/build lead: Owner of [EcstaceeLOR/CertiFiks](https://github.com/EcstaceeLOR/CertiFiks); no external builders claimed
- Track: *Proposed* Modular Cloud & Middleware; verify exact options
- Repo and main commit: link to public source and release SHA (do not use branch with unfinished work as complete)
- Current build: architecture, API/Next scaffold, deterministic domain hash, historical unsafe Solidity baseline, tests; no real escrow
- Open blockers: V3 testnet, contracts/withdrawal fairness, real GitHub App, secure runner, role-complete E2E
- Product architecture: [live Markdown diagram](../architecture/COMPETITION_ARCHITECTURE.md)
- Contract/testnet deployment: **NOT AVAILABLE / BLOCKED**, supply only authentic future evidence
- Real demo URL/video: **NOT AVAILABLE** until a core interaction is operable
- Initial proof: [CI builds and vulnerability characterization](https://github.com/EcstaceeLOR/CertiFiks/actions)
- GitHub history: [commits](https://github.com/EcstaceeLOR/CertiFiks/commits/main/), [PRs](https://github.com/EcstaceeLOR/CertiFiks/pulls?q=is%3Apr)
- Check-in submitted? **NO**; record the actual DoraHacks submission confirmation, never infer it.

## 7. Exact field verification outstanding (not silently marked done)

- [ ] Log in to the actual [DoraHacks event](https://dorahacks.io/hackathon/2362/detail), inspect Build/check-in form and confirm track list, mandatory fields, country eligibility and cutoff countdown against the mirror.
- [ ] Verify whether contract address and tx hash are mandatory at check-in or only final; the secondary description contains both a strong check-in request for them and 'if available' explorer wording.
- [ ] Obtain organizer confirmation of approved Portaldot V3 endpoint, faucet, explorer and deployment type (#18). If chain not available, ask how eligibility is treated rather than substituting local legacy node proof.
- [ ] Confirm use of pre-existing ProofPatch source reworked during the building period satisfies originality criteria. Preserve provenance.
- [ ] Capture real check-in submission proof once accepted on DoraHacks and add immutable references to the evidence ledger.
- [ ] Reopen official submission form just before final; check required URLs, video max length, pitch, code freeze, testnet hashes, KYC/prize terms; submit then capture receipt.

**Release gate:** [scripts/check-submission-readiness.mjs](../../scripts/check-submission-readiness.mjs) validates the local evidence ledger. It is **advisory** by default; `--require-checkin` and `--require-final` fail explicitly until genuine artifacts are recorded. Do not let a green CI format/test check be misinterpreted as submission readiness.

## 8. Decision for Issue #8
The **rules research + evidence tracker + architecture diagram** can be reviewed and merged now. However, the issue's strict final two acceptance items require an *actual working check-in package and review of the official final submission*. Those actions are **not yet possible** and must not be falsely ticked off. Keep #8 OPEN for verification/closeout, use #45 to coordinate actual submission, and continue engineering under the user's explicit consent to advance while externally dependent work remains open.

This split preserves truth without stopping development of the real product. The organizer, not this repo, determines eligibility.
