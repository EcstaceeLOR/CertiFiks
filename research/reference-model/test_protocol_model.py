"""Historical reference-model tests; not proof of safe escrow or deployed contracts."""
import unittest
from protocol_model import Bounty, State, Invalid

class TestCertiFiksHistoricalModel(unittest.TestCase):
    def setUp(self):
        self.b = Bounty("sponsor", 1000, "sha256:test-spec", ("ver1", "ver2"), "judge", 1000, 100, 10)
        self.b.assign("sponsor", "dev", 0)

    def test_happy_path(self):
        self.b.submit("dev", "commit:abc", 10)
        self.b.verify("ver1", True, "report:a", 20)
        self.b.verify("ver2", True, "report:b", 21)
        with self.assertRaises(Invalid):
            self.b.settle(30)
        self.b.settle(31)
        self.assertEqual((self.b.status, self.b.paid_to, self.b.reward), (State.PAID, "dev", 0))

    def test_no_payout_with_one_verifier(self):
        self.b.submit("dev", "commit:abc", 10)
        self.b.verify("ver1", True, "report:a", 20)
        with self.assertRaises(Invalid):
            self.b.settle(300)

    def test_reject_unknown_verifier(self):
        self.b.submit("dev", "commit:abc", 10)
        with self.assertRaises(Invalid):
            self.b.verify("random", True, "report", 12)

    def test_reject_duplicate_verifier(self):
        self.b.submit("dev", "commit:abc", 10)
        self.b.verify("ver1", True, "report", 12)
        with self.assertRaises(Invalid):
            self.b.verify("ver1", True, "report", 12)

    def test_negative_verdict_escalates_dispute(self):
        self.b.submit("dev", "commit:abc", 10)
        self.b.verify("ver1", True, "report:a", 20)
        self.b.verify("ver2", False, "report:b", 21)
        self.assertEqual(self.b.status, State.DISPUTED)
        with self.assertRaises(Invalid):
            self.b.settle(100)
        self.b.resolve("judge", False)
        self.assertEqual(self.b.paid_to, "sponsor")

    def test_challenge_dispute_arbitration(self):
        self.b.submit("dev", "commit:abc", 10)
        self.b.verify("ver1", True, "report:a", 20)
        self.b.verify("ver2", True, "report:b", 21)
        self.b.challenge("sponsor", "sponsor:reason", 22)
        with self.assertRaises(Invalid):
            self.b.settle(40)
        self.b.resolve("judge", True)
        self.assertEqual(self.b.paid_to, "dev")

    def test_no_double_payout(self):
        self.b.submit("dev", "commit:abc", 10)
        self.b.verify("ver1", True, "report:a", 20)
        self.b.verify("ver2", True, "report:b", 21)
        self.b.settle(31)
        with self.assertRaises(Invalid):
            self.b.settle(31)

    def test_sponsor_cannot_cancel_accepted_job(self):
        self.b.submit("dev", "commit:abc", 10)
        with self.assertRaises(Invalid):
            self.b.refund_expired("sponsor", 20)

    def test_historical_unsafe_timeout_refund_is_reproduced(self):
        # KNOWN VULNERABILITY to eliminate in #6/#15: valid timely submission, no reviewers,
        # then sponsor receives a refund. This is characterization, not desired behavior.
        self.b.submit("dev", "commit:abc", 10)
        self.b.refund_expired("sponsor", 111)
        self.assertEqual(self.b.status, State.REFUNDED)

    def test_no_new_submission_after_deadline(self):
        with self.assertRaises(Invalid):
            self.b.submit("dev", "commit:abc", 1001)

    def test_unassigned_wallet_cannot_submit(self):
        with self.assertRaises(Invalid):
            self.b.submit("ver1", "commit:abc", 10)

    def test_cannot_replace_assigned_developer(self):
        with self.assertRaises(Invalid):
            self.b.assign("sponsor", "hijacker", 5)

    def test_no_empty_report(self):
        self.b.submit("dev", "commit:abc", 10)
        with self.assertRaises(Invalid):
            self.b.verify("ver1", True, "", 12)

    def test_arbiter_cannot_override_approved_without_dispute(self):
        self.b.submit("dev", "commit:abc", 10)
        self.b.verify("ver1", True, "report:a", 20)
        self.b.verify("ver2", True, "report:b", 21)
        with self.assertRaises(Invalid):
            self.b.resolve("judge", False)

if __name__ == "__main__":
    unittest.main()
