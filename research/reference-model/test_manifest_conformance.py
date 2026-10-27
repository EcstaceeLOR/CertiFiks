"""Manifest hashing conformance across TypeScript and Python.

The Python v1 reference supports Unicode and UTF-16 key ordering for the
integer-only I-JSON schema subset. Floating-point serialization remains
explicitly unsupported (it must fail, rather than silently diverge).
"""
import copy
import json
import unittest
from pathlib import Path

from protocol_hash_reference import canonical_ijson_v1, digest_manifest_example

VECTORS = Path(__file__).resolve().parents[2] / "protocol" / "vectors"


class ManifestConformanceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.golden = json.loads((VECTORS / "manifest-v1.json").read_text())
        cls.cases = json.loads((VECTORS / "manifest-tamper-v1.json").read_text())

    def test_golden_manifest_sha256(self):
        self.assertEqual(
            digest_manifest_example(self.golden["input"]),
            self.golden["expected"],
        )

    def test_unicode_utf16_order_and_escape_vector(self):
        fixture = json.loads(
            (VECTORS / "manifest-unicode-v1.json").read_text(encoding="utf-8")
        )
        self.assertEqual(
            digest_manifest_example(fixture["input"]), fixture["expected"]
        )
        serialized = canonical_ijson_v1(fixture["input"]).decode("utf-8")
        self.assertLess(serialized.index("😀"), serialized.index("\ue000"))
        changed = copy.deepcopy(fixture["input"])
        changed["strings"]["😀"] = "different face"
        self.assertNotEqual(digest_manifest_example(changed), fixture["expected"])

    def test_unsafe_numbers_and_surrogates_fail_closed(self):
        for value in [float("nan"), 0.5, 2**53, {1: "bad key"}, "\ud800"]:
            with self.subTest(value=repr(value)):
                with self.assertRaises((ValueError, TypeError, UnicodeError)):
                    canonical_ijson_v1({"invalid": value})

    def test_each_sensitive_field_changes_hash(self):
        for entry in self.cases["tampering"]:
            with self.subTest(path=entry["path"]):
                copied = copy.deepcopy(self.golden["input"])
                target = copied
                for segment in entry["path"][:-1]:
                    target = target[segment]
                target[entry["path"][-1]] = entry["value"]
                self.assertNotEqual(
                    digest_manifest_example(copied),
                    self.golden["expected"],
                )


if __name__ == "__main__":
    unittest.main()
