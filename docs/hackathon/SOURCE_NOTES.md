# Portaldot Hacker House 2026 — Source reliability and unresolved decisions

**Issue #8. Reviewed 2026-10-15.**

## Confirmed in organizer-origin public event copy
- [Eventbrite listing by DoraHacks](https://www.eventbrite.com/e/portaldot-hacker-house-2026-tickets-2002321816454) — online event Oct 14–Nov 6; published description welcomes **individual** builders as well as teams; Portaldot V3.0 advertised to support both EVM and WASM contract execution; links to [the DoraHacks competition](https://dorahacks.io/hackathon/2362/detail).
- Existence of public Eventbrite listing and a linked official submission site **does not prove** any individual participant is registered, eligible for prizes, or able to deploy a contract.
- Live authenticated organizer-specific DoraHacks form was not inspected because public web retrieval returned 405/blocked; operator manual check is required.

## Reproduced secondary text — unconfirmed until organizer corroboration
[HackathonRadar event copy](https://www.hackathonradar.com/database/hackathon/portaldot-hacker-house-2026) currently reports:
- Check-in Oct 24 20:00 UTC+8 -> **Oct 24 13:00 WAT**.
- Final / code freeze Nov 6 12:00 UTC+8 -> **Nov 6 05:00 WAT**.
- 4 tracks including Modular Cloud & Middleware; judges' weights 30 technical, 30 innovation, 20 ecosystem, 20 business.
- Check-in expects progress, repo, README, architecture, Portaldot testnet address/tx and live link OR ≤3min video; a core function should already work. Check-in demo may use simulated data (our founder-ready bar is stricter).
- Final expects runnable source, testnet proof, demo, 3-minute video, pitch deck.
- Public repo, >=3 real commits during event, mostly new code, no last-minute one-drop of core modules and freeze after deadline.
- Prize pool reportedly 5200 USDT equivalent (2600 USDT and 2600 POT equivalent); grand prize 1000, track first 800; amount/eligibility **not guaranteed**.
- An open-source SDK/reference baseline is allowed if credited, but representing a pre-existing complete project as new work is disallowed.

### Sources that must not be silently mistaken for this 2026 competition
- Prior Portaldot **Mini Season 1** rules about qualifying local nodes do not determine V3 Hacker House eligibility.
- Public legacy Portaldot mainnet RPC tests from CertiFiks [#2](./network.md) do not establish the separate V3 testnet.
- Third-party projects' testnet screenshots/claims do not count as CertiFiks deployment receipts.
- Generic DoraHacks organizer dashboard sandbox pages do **not** prove requirements for this particular 2026 Hacker House.

## Organizer clarification request (not yet sent)
1. What is the definitive approved V3 testnet RPC (HTTP/WS), genesis hash/chain ID, faucet and explorer for both EVM and WASM? Does a local or third-party endpoint qualify?
2. Is the check-in mandatory to remain prize-eligible? Is a testnet address/transaction required **at check-in**, or only final; what do you accept if a public V3 faucet is unavailable?
3. Can a **solo Nigerian developer** participate and receive USDT/POT prizes, and what KYC/tax or wallet payout restrictions apply?
4. Does rebuilding a historical non-deployed Solidity study starter into a largely new product during October 14–November 6 satisfy originality? How are public PR/commit histories assessed?
5. Is the precise Oct 24 13:00 WAT and Nov 6 05:00 WAT schedule still correct on DoraHacks, including the check-in timezone?
6. Can one user submit more than one build? Not essential to CertiFiks but not independently verified.

Answers should be cited verbatim with date and person/source when obtained. **Do not assume silence implies approval.**
