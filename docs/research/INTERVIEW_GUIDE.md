# CertiFiks — consent-first discovery interviews and recruiting scripts

**Issue:** #7 · **Status:** Prepared, NOT SENT · **No fictional interview answers**
**Participation:** Voluntary; no guaranteed payment, outside GitHub PR assignment or funding; do not collect sensitive code, identity documents, wallet keys or financial information.

## Recruiting cohorts
- Three independent maintainers or issue/bounty sponsors, including at least one from a small OSS project and one security-conscious maintainer; avoid treating repeated members of the same team as three independent buyers.
- Three potential paid contributors with different experience levels and payment preferences, not merely three accounts managed by one person. Recruiting GitHub contributors may require approved discussions/community channels, not drive-by issue spam.
- Candidate maintainer starting points: OpenZeppelin docgen plugin owner on #6805, OpenEverest issue triager on #3357. **Names, permissions, interest and willingness are unknown** until actual contact. Use a third OSS maintainer only after identifying an appropriate opt-in channel.

## Outreach to maintainer (public GitHub discussion or permissioned email)
Subject: Could I learn how you verify and reward external bug fixes?

> Hi — I'm building CertiFiks, a software-fix payment workflow, and I'm researching how maintainers decide when a bug is actually fixed. I came across [specific open issue] and its reproduction steps.
>
> Would you be open to a 15-minute feedback conversation? I'm not asking you to install anything or fund a bounty. If it seems useful, I would propose an optional no-money pilot only after we agree on an immutable test and privacy rules. It's completely fine if not. I won't post repeated follow-ups.

## Outreach to contributor (voluntary community / colleague)
Subject: Research interview on open-source bug-fix rewards

> Hi — I'm researching why developers do or don't take on paid GitHub bug fixes. Would you be willing to spend 15 minutes talking about how acceptance, merge delays, and payout timing have worked for you? There is no investment or wallet setup needed and no promised work. I can keep your feedback anonymous if you prefer.

## Neutral maintainer interview (avoid leading questions)
1. Tell me about the last time an outsider submitted a bug fix. How did you determine it was complete?
2. Who could reject the fix, and what evidence did they look at? Was CI enough, or did you need judgment/manual reproduction?
3. Have you paid or promised a reward for an issue? What went wrong, if anything? How did you handle a rejected fix?
4. Would a locked baseline-fails/candidate-passes test have changed the decision? For which kinds of bugs would it be inadequate?
5. What would make an externally hosted test runner or verifier unacceptable: private code, credentials, time, ongoing maintenance, or cost?
6. When a PR merges, do you consider the fix finished? Why/why not?
7. What extra delay, dispute rules and verification charge would be the maximum acceptable in an actual job? Ask for a choice and reason, not a generic 'yes'.
8. If we ran one **no-money** pilot on an issue you choose, what would you require and what would cause you to say no?
9. Ask whether notes may be recorded or quoted, whether to anonymize, and whether follow-up contact is acceptable.

## Neutral contributor interview
1. Tell me about the last paid or promised-pay open-source contribution; what happened between submitting and receiving compensation?
2. What part of accepting a bounty feels riskiest: unclear requirements, sponsor refusal, payment country restrictions, reviewer delays, fees or wallet onboarding?
3. Would you prefer PR merge, tests plus human review, or explicit sponsor signoff as the payout criterion? What would you give up to gain certainty?
4. Would you accept immutable tests published before starting? How would you dispute tests that were wrong or incomplete?
5. What is the longest review + dispute period you'd accept for $20, $100 and $500 work, and why?
6. What payout methods can you genuinely receive today? Don't ask for banking details, seed phrases or specific wallet addresses.
7. Would you volunteer for a **no-money technical dry run**, knowing that it does not guarantee later work or rewards? What would make it worth the time?
8. Ask for consent on any notes, attribution and follow-up.

## Evidence capture template (private research, NOT public commit)
- Participant pseudonym / type (maintainer, contributor, or sponsor):
- Date and channel:
- Consent for conversation? Consent for quote and public attribution? (separate yes/no):
- Existing workflow with specific anecdote:
- Last real observed friction:
- Desired acceptance and payout rules:
- Price / time / trust thresholds (record expressed figure, not your estimate):
- Biggest deal breaker:
- Pilot opt-in to existing real bug? Which issue URL, and exact allowed scope:
- Follow-up permissions:
- Verbatim consented quote (optional):
- Researcher interpretation clearly separated from direct statement:

For public docs only publish counts and anonymized summaries if participants approved. Never pretend comments on somebody else's GitHub issue constitute a research interview.

## Screening and no-go decision
**GO to consented no-money pilot** if an actual maintainer selects a real issue and test, confirms repository control and participants accept confidentiality + timeouts. **NO-GO** if no buyers want extra proof beyond merge, costs exceed reward, reviewers cannot be independent, private code can't be isolated or adjudication cannot terminate safely.

**Funded product launch remains separately blocked** by #14/#15/#17/#18/#21/#41, regardless of positive interviews.
