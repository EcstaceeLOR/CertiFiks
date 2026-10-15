"""Manifest tampering conformance for the ASCII/I-JSON v1 fixture subset.

The Python reference is intentionally not a general Unicode RFC8785 encoder.
It independently tests the bytes/fields covered by published conformance data.
"""
import copy
import json
import unittest
from pathlib import Path

from protocol_hash_reference import digest_manifest_example

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
