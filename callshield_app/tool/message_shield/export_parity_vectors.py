"""Export golden feature/hash vectors so the Dart mirror can be verified.

Usage:
    python tool/message_shield/export_parity_vectors.py

Writes test/message_shield/parity_vectors.json, which
test/message_shield/ml_hashing_parity_test.dart loads and checks against the
Dart implementation in lib/message_shield/engine/features.dart. If the two
implementations ever drift, that test fails instead of the shipped model
silently producing different features on device.
"""

from __future__ import annotations

import json
from pathlib import Path

from features import DEFAULT_BUCKETS, featurize, fnv1a32, hashed_index, vector

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = ROOT / "test" / "message_shield" / "parity_vectors.json"

MESSAGES = [
    "Dear customer, your KYC is expired. Update immediately at http://sbi-kyc-update.xyz/verify or your account will be blocked.",
    "482913 is your OTP for SBI net banking login. Do not share this code with anyone, including bank staff.",
    "sir otp bhejo warna a/c band ho jayega, 0TP share karein turant!!",
    "Your parcel is held at customs, pay the clearance fee of Rs.1,250 at http://customs-clearance.help/pay",
    "Hey, are we still meeting at 7? Let me know. Sent from my iPhone",
    "आपका OTP {digits} है, अधिकारी को शेयर करें वरना खाता बंद हो जाएगा।".replace("{digits}", "482913"),
    "CONGRATULATIONS!! You won Rs.10,00,000 in the lucky draw, pay Rs.4,999 processing fee to claim.",
]

HASH_SAMPLES = [
    "u:otp", "u:kyc", "u:num", "b:your_otp", "c:urit", "su:otp", "sb:share_karein",
    "f:has_url", "f:caps_heavy", "sc:अधिक", "u:₹", "f:mixed_script", "c:ition", "b:num_karein",
]


def main() -> None:
    payload = {
        "feature_version": "fm-2",
        "buckets": DEFAULT_BUCKETS,
        "hashes": [
            {
                "feature": f,
                "hash": fnv1a32(f),
                "bucket": hashed_index(f)[0],
                "sign": hashed_index(f)[1],
            }
            for f in HASH_SAMPLES
        ],
        "messages": [
            {
                "text": text,
                "features": featurize(text),
                "vector": {str(k): v for k, v in sorted(vector(text).items())},
            }
            for text in MESSAGES
        ],
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"wrote {OUT} with {len(payload['messages'])} messages and {len(payload['hashes'])} hashes")


if __name__ == "__main__":
    main()
