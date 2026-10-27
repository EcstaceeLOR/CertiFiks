# Issue #46 — Unit economics and verification service pricing

**Status: deterministic planning worksheet, NOT real customer traction, measured operating costs, or an enabled fee schedule.**

All amounts here are artificial **USD cents**, not blockchain atomic token amounts. The example does not set platform fees, modify contract constants, or enable a billing endpoint. Production financial, legal and network assumptions remain unverified.

Run:

```sh
npm run economics:test
npm run economics:plan
node scripts/business/unit-economics.mjs /path/to/your/approved-private-scenario.json
```

The reproducible JSON worksheet is at `scripts/business/unit-economics.example.json`; the calculator is at `scripts/business/unit-economics.mjs`. All inputs are explicitly marked `synthetic_planning_only` and must include each monthly fixed cost, a prospective sponsor-paid platform charge per **completed** bounty, direct verification runs and retry budget, reviewer compensation, artifact retention, RPC, support, expected dispute rate/case cost and timeout rate/case cost. Input cent values must be non-negative safe integers. The two event rates are in basis points and cannot add to more than 100%; no imaginary double-counting or floating-point rounding occurs.

### Synthetic example (not observed)

- Assumed 40 completed bounties/month, sponsor fee **$18.00 per completed bounty** (unapproved and not charged).
- Per-bounty direct costs: 2 verification runs × $1.00, reviewers $6.00, retained artifacts $0.40, RPC $0.40, and support $2.00 = **$10.80**.
- Scenario risk: 10% disputes costing $15.00 each, and 5% timeouts costing $5.00 each = **$1.75** expected additional cost per bounty.
- Per-completion expected variable cost: **$12.55**. Fixed monthly costs: hosting $80, monitoring $30, backup $20, compliance $60 = **$190.00**.
- Monthly revenue at the hypothetical $18 fee = **$720.00**. Scenario costs = $502 variable + $190 fixed = **$692.00**; hypothetical surplus = **$28.00**.
- Break-even: **35 completed bounties per month**, at these unverified unit assumptions. If marginal revenue does not exceed costs, break-even returns `null` rather than falsely promising profitability.

This arithmetic applies conservative upward rounding for expected cent-level costs and uses `BigInt` internally. It does **not** include unknown chain gas, price volatility, fiat/payment processing or taxes beyond the explicitly supplied input assumptions. Operators must model these costs before launch, or document why they do not apply.

### Missing acceptance evidence

- Measure actual runner CPU/network minutes, object-store bytes and retention durations, verifier compensation, RPC costs, failed retries, support and disputes on at least two independent pilot cases.
- Validate whether real maintainers prefer per-bounty sponsor fees, subscription or transparent hybrid charges. Do not represent uncollected survey or market responses as results.
- Before implementation, make proposed fees a transparent signed quote bound to exact on-chain and API calculations, never silently deduct from contributor escrow rewards.
- Quantify live refund/dispute and arbitration cost exposure, private repository enterprise burden, secure worker infrastructure and staffing; review payment compliance and fee custody.
- Re-run the model with provider invoices and pilot data, and obtain business owner review; then decide what to publish as actual pricing.

Keep Issue #46 OPEN until the genuine measured and independent pilot evidence is attached.
