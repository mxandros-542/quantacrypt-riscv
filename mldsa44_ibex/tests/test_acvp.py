"""NIST ACVP byte-for-byte checks, using the vendored public test vectors.

Checks the public pure-ML-DSA API and private internal message interface.
HashML-DSA/prehash and caller-supplied mu are outside this package's API.
"""
import ctypes as c
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VECTORS = ROOT / "tests/vectors"
lib = c.CDLL(str(ROOT / "build/libmldsa44.so"))
keygen = lib.mldsa44_keypair_from_seed
keygen.argtypes = [c.c_void_p, c.c_void_p, c.c_char_p]
keygen.restype = c.c_int
sign_args = [c.c_void_p, c.POINTER(c.c_size_t), c.c_char_p, c.c_size_t,
             c.c_char_p, c.c_size_t, c.c_char_p, c.c_char_p]
verify_args = [c.c_char_p, c.c_size_t, c.c_char_p, c.c_size_t,
               c.c_char_p, c.c_size_t, c.c_char_p]
for name in ["mldsa44_sign", "mldsa44_core_sign"]:
    getattr(lib, name).argtypes = sign_args
    getattr(lib, name).restype = c.c_int
for name in ["mldsa44_verify", "mldsa44_core_verify"]:
    getattr(lib, name).argtypes = verify_args
    getattr(lib, name).restype = c.c_int

def load(name):
    return json.loads((VECTORS / f"ML-DSA-{name}-FIPS204.json").read_text())

def raw(test, name, default=""):
    return bytes.fromhex(test.get(name, default))

def require(condition, label):
    if not condition:
        raise RuntimeError(label)

def supported(group):
    if group.get("externalMu", False):
        return False
    return group["signatureInterface"] == "internal" or group["preHash"] == "pure"

counts = {"keygen": 0, "sign_external": 0, "sign_internal": 0,
          "verify_external": 0, "verify_internal": 0, "skipped_outside_api": 0}

for group in load("keyGen")["testGroups"]:
    for test in group["tests"]:
        label = f"keyGen tcId={test['tcId']}"
        pk, sk = c.create_string_buffer(1312), c.create_string_buffer(2560)
        require(keygen(pk, sk, raw(test, "seed")) == 0, label + " status")
        require(pk.raw == raw(test, "pk"), label + " public key mismatch")
        require(sk.raw == raw(test, "sk"), label + " private key mismatch")
        counts["keygen"] += 1

for group in load("sigGen")["testGroups"]:
    if not supported(group):
        counts["skipped_outside_api"] += len(group["tests"])
        continue
    external = group["signatureInterface"] == "external"
    sign = lib.mldsa44_sign if external else lib.mldsa44_core_sign
    verify = lib.mldsa44_verify if external else lib.mldsa44_core_verify
    for test in group["tests"]:
        label = f"sigGen tgId={group['tgId']} tcId={test['tcId']}"
        message = raw(test, "message")
        prefix_or_context = raw(test, "context") if external else b""
        rnd = bytes(32) if group["deterministic"] else raw(test, "rnd")
        signature, length = c.create_string_buffer(2420), c.c_size_t()
        status = sign(signature, c.byref(length), message, len(message),
                      prefix_or_context, len(prefix_or_context), rnd, raw(test, "sk"))
        require(status == 0 and length.value == 2420, label + " signing status")
        require(signature.raw == raw(test, "signature"), label + " signature mismatch")
        require(verify(signature.raw, length.value, message, len(message),
                       prefix_or_context, len(prefix_or_context), raw(test, "pk")) == 0,
                label + " generated signature verification")
        counts["sign_external" if external else "sign_internal"] += 1

for group in load("sigVer")["testGroups"]:
    if not supported(group):
        counts["skipped_outside_api"] += len(group["tests"])
        continue
    external = group["signatureInterface"] == "external"
    verify = lib.mldsa44_verify if external else lib.mldsa44_core_verify
    for test in group["tests"]:
        label = f"sigVer tgId={group['tgId']} tcId={test['tcId']}"
        message, signature = raw(test, "message"), raw(test, "signature")
        prefix_or_context = raw(test, "context") if external else b""
        valid = verify(signature, len(signature), message, len(message),
                       prefix_or_context, len(prefix_or_context), raw(test, "pk")) == 0
        require(valid == test["testPassed"], label + " validity mismatch")
        counts["verify_external" if external else "verify_internal"] += 1

require(all(counts[name] > 0 for name in counts if name != "skipped_outside_api"),
        "Expected validation groups were not exercised")
result = {"result": "PASS", "counts": counts,
          "scope": "Pure ML-DSA-44 external API and internal byte-message routines",
          "excluded": "HashML-DSA/prehash and external-mu interfaces are not implemented",
          "source": json.loads((VECTORS / "SOURCES.json").read_text(encoding="utf-8-sig"))}
(ROOT / "build/validation_acvp.json").write_text(json.dumps(result, indent=2) + "\n")
print("PASS: NIST ACVP known-answer tests")
for name, count in counts.items():
    print(f"  {name}: {count}")
