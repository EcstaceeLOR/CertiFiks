"""Historical ProofPatch deterministic reference model (unreviewed; NOT the CertiFiks production protocol).

Known unsafe historical behavior: refund_expired() allows sponsor refund after a timely
submission when verifiers time out. This is a security flaw, NOT an approved product rule.
See docs/security/THREAT_MODEL.md and issues #6, #14, #15.
"""
from dataclasses import dataclass, field
from enum import Enum

class State(str, Enum):
    OPEN = "open"
    SUBMITTED = "submitted"
    APPROVED = "approved"
    DISPUTED = "disputed"
    PAID = "paid"
    REFUNDED = "refunded"

class Invalid(Exception):
    pass

@dataclass
class Bounty:
    sponsor: str
    reward: int
    spec_hash: str
    verifiers: tuple[str, str]
    arbitrator: str
    deadline: int
    verification_window: int
    challenge_window: int
    status: State = State.OPEN
    developer: str | None = None
    submission_hash: str | None = None
    submitted_at: int | None = None
    approved_at: int | None = None
    verdicts: dict = field(default_factory=dict)
    paid_to: str | None = None

    def assign(self, actor: str, developer: str, now: int):
        if actor != self.sponsor or self.status != State.OPEN or now > self.deadline or self.developer is not None or developer in ("", self.sponsor, *self.verifiers, self.arbitrator):
            raise Invalid("not assignable")
        self.developer = developer

    def submit(self, actor: str, submission_hash: str, now: int):
        if self.status != State.OPEN or now > self.deadline or not submission_hash or actor != self.developer:
            raise Invalid("not eligible to submit")
        self.submission_hash, self.submitted_at, self.status = submission_hash, now, State.SUBMITTED

    def verify(self, actor: str, passed: bool, report_hash: str, now: int):
        if self.status != State.SUBMITTED or actor not in self.verifiers or actor in self.verdicts or not report_hash or now > self.submitted_at + self.verification_window:
            raise Invalid("invalid attestation")
        self.verdicts[actor] = (passed, report_hash)
        if len(self.verdicts) == 2:
            if all(v[0] for v in self.verdicts.values()):
                self.status, self.approved_at = State.APPROVED, now
            else:
                self.status = State.DISPUTED

    def challenge(self, actor: str, reason_hash: str, now: int):
        if self.status != State.APPROVED or actor != self.sponsor or now >= self.approved_at + self.challenge_window or not reason_hash:
            raise Invalid("not challengeable")
        self.status = State.DISPUTED

    def settle(self, now: int):
        if self.status != State.APPROVED or now < self.approved_at + self.challenge_window:
            raise Invalid("cannot settle")
        self.status, self.paid_to, self.reward = State.PAID, self.developer, 0

    def resolve(self, actor: str, pay_developer: bool):
        if self.status != State.DISPUTED or actor != self.arbitrator:
            raise Invalid("not arbitrator")
        self.status, self.paid_to, self.reward = (State.PAID if pay_developer else State.REFUNDED), (self.developer if pay_developer else self.sponsor), 0

    def refund_expired(self, actor: str, now: int):
        if actor != self.sponsor or not ((self.status == State.OPEN and now > self.deadline) or (self.status == State.SUBMITTED and now > self.submitted_at + self.verification_window)):
            raise Invalid("not expired")
        self.status, self.paid_to, self.reward = State.REFUNDED, self.sponsor, 0
