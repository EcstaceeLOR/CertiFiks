"""Independent Python v1 hash vector implementation (ASCII/I-JSON fixture only).

This demonstrates fixed-width SHA-256 compatibility with Solidity/TS. For
general JSON canonicalization (Unicode, floating point) use a reviewed RFC8785
implementation; the shared package uses the npm canonicalize library.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VECTORS = ROOT / "protocol" / "vectors"


def _u(value: str, nbytes: int) -> bytes:
    if value != str(int(value)) or int(value) < 0 or int(value) >= 2 ** (nbytes * 8):
        raise ValueError("noncanonical or out-of-range uint")
    return int(value).to_bytes(nbytes, "big")


def digest_attempt(data: dict) -> str:
    fields = (
        b"CertiFiks:attempt-attestation:v1\0"
        + bytes.fromhex(data["chainGenesis"][2:])
        + bytes.fromhex(data["contractLocatorHash"][2:])
        + _u(data["bountyId"], 32)
        + _u(data["attemptId"], 8)
        + _u(data["repositoryId"], 32)
        + bytes.fromhex(data["baseCommitSha"])
        + bytes.fromhex(data["headCommitSha"])
        + bytes.fromhex(data["manifestDigest"][2:])
        + bytes.fromhex(data["imageDigest"][2:])
        + bytes.fromhex(data["resultDigest"][2:])
        + _u(data["expiryUnix"], 8)
    )
    return "0x" + hashlib.sha256(fields).hexdigest()


def digest_manifest_example(data: dict) -> str:
    # This test fixture uses the RFC8785-compatible subset (ASCII + integer numbers).
    encoded = json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return "0x" + hashlib.sha256(b"CertiFiks:manifest:v1\0" + encoded).hexdigest()


if __name__ == "__main__":
    a = json.loads((VECTORS / "attestation-v1.json").read_text())
    m = json.loads((VECTORS / "manifest-v1.json").read_text())
    assert a["version"] == m["version"] == "1"
    assert digest_attempt(a["input"]) == a["expected"]
    assert digest_manifest_example(m["input"]) == m["expected"]
    print("PASS: independent Python attestation and manifest hash vectors")
