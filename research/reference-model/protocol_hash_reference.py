"""Independent Python CertiFiks v1 commitment reference.

Supports the manifest protocol's I-JSON subset: strings, Unicode keys,
boolean/null, arrays, maps, and exactly representable safe integers. Keys
sort by UTF-16 code units as in ECMAScript JSON.stringify / RFC8785. It
intentionally rejects floats and invalid Unicode instead of pretending to
provide a fully general RFC8785 floating-point encoder.
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


def canonical_ijson_v1(value) -> bytes:
    """Produce canonical UTF-8 for v1 I-JSON values; fail on unsafe types.

    Python's default sort_keys sorts Unicode codepoints, not UTF-16 units,
    which differs from JavaScript for supplementary-plane keys versus keys
    near U+E000. Reject unsafe JSON numbers and lone surrogate codepoints.
    """
    def serialize(item):
        if item is None:
            return "null"
        if item is True:
            return "true"
        if item is False:
            return "false"
        if isinstance(item, str):
            item.encode("utf-8", errors="strict")
            return json.dumps(item, ensure_ascii=False, separators=(",", ":"))
        if isinstance(item, int):
            if abs(item) > 2**53 - 1:
                raise ValueError("integer not exactly representable by JavaScript")
            return str(item)
        if isinstance(item, list):
            return "[" + ",".join(serialize(v) for v in item) + "]"
        if isinstance(item, dict):
            if any(not isinstance(k, str) for k in item):
                raise TypeError("JSON object keys must be strings")
            keys = sorted(item, key=lambda k: k.encode("utf-16-be", errors="strict"))
            return "{" + ",".join(
                serialize(k) + ":" + serialize(item[k]) for k in keys
            ) + "}"
        raise TypeError("unsupported I-JSON value (including floats)")

    return serialize(value).encode("utf-8", errors="strict")


def digest_manifest_example(data: dict) -> str:
    encoded = canonical_ijson_v1(data)
    return "0x" + hashlib.sha256(b"CertiFiks:manifest:v1\0" + encoded).hexdigest()


if __name__ == "__main__":
    a = json.loads((VECTORS / "attestation-v1.json").read_text())
    m = json.loads((VECTORS / "manifest-v1.json").read_text())
    assert a["version"] == m["version"] == "1"
    assert digest_attempt(a["input"]) == a["expected"]
    assert digest_manifest_example(m["input"]) == m["expected"]
    print("PASS: independent Python attestation and manifest hash vectors")
