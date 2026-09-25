"""Message Shield ML feature spec (REFERENCE implementation).

The Dart mirror lives in:
  lib/message_shield/engine/preprocessor.dart
  lib/message_shield/engine/ml_engine.dart

If you change anything here you MUST mirror it in Dart and re-run:
  tool/message_shield/train_model.py        (regenerates the shipped weights)
  test/message_shield/ml_hashing_parity_test.dart
                                          (guards Dart/Python parity)

Feature space (version fm-2):
  u:<token>                 unigram over normalized tokens (digit runs -> "num")
  b:<t1>_<t2>               bigram over consecutive normalized tokens
  c:<4gram>                 char 4-gram inside tokens of length >= 5
                            (first 12 qualifying tokens, at most 240 grams)
  su:/sb:/sc:               the same three, computed on the leet-folded skeleton
                            view so "0tp" and "otp" land in nearby feature space
  f:<flag>                  message level binary flags

Hashing: FNV-1a 32-bit over the UTF-8 bytes of the feature string.
  bucket = hash % buckets
  sign   = -1 when bit 31 of the hash is set, else +1
Values are binary presence (1.0). Duplicate features collapse.
"""

from __future__ import annotations

import re

FEATURE_VERSION = "fm-2"
DEFAULT_BUCKETS = 8192

# ---------------------------------------------------------------------------
# Normalization
# ---------------------------------------------------------------------------

# Zero width / bidi control / soft hyphen / variation selectors.
_ZERO_WIDTH = (
    "\u200b\u200c\u200d\u200e\u200f"
    "\u202a\u202b\u202c\u202d\u202e"
    "\ufeff\u00ad\ufe0e\ufe0f"
)

# Unicode space separators -> plain space.
_SPACE_LIKE = "\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000"

# Common confusable characters (Cyrillic / Greek / fullwidth) -> ASCII.
HOMOGLYPHS = {
    "\u0430": "a", "\u0435": "e", "\u043e": "o", "\u0440": "p", "\u0441": "c",
    "\u0445": "x", "\u0443": "y", "\u043a": "k", "\u043c": "m", "\u0442": "t",
    "\u0432": "b", "\u043d": "h", "\u0456": "i", "\u0455": "s", "\u0458": "j",
    "\u04bb": "h", "\u0501": "d", "\u051b": "q", "\u051d": "w",
    "\u03b1": "a", "\u03b2": "b", "\u03b5": "e", "\u03b7": "n", "\u03b9": "i",
    "\u03ba": "k", "\u03bc": "u", "\u03bd": "v", "\u03bf": "o", "\u03c1": "p",
    "\u03c3": "o", "\u03c4": "t", "\u03c5": "u", "\u03c7": "x",
    "\uff41": "a", "\uff45": "e", "\uff4f": "o", "\uff50": "p", "\uff43": "c",
    "\uff44": "d", "\uff46": "f", "\uff47": "g", "\uff48": "h", "\uff49": "i",
    "\uff4a": "j", "\uff4b": "k", "\uff4c": "l", "\uff4d": "m", "\uff4e": "n",
}

# Latin letters with diacritics -> base letter (cheap NFKD-ish fold).
DIACRITICS = {
    "\u00e0": "a", "\u00e1": "a", "\u00e2": "a", "\u00e3": "a", "\u00e4": "a", "\u00e5": "a",
    "\u00e7": "c", "\u00e8": "e", "\u00e9": "e", "\u00ea": "e", "\u00eb": "e",
    "\u00ec": "i", "\u00ed": "i", "\u00ee": "i", "\u00ef": "i",
    "\u00f1": "n", "\u00f2": "o", "\u00f3": "o", "\u00f4": "o", "\u00f5": "o", "\u00f6": "o",
    "\u00f9": "u", "\u00fa": "u", "\u00fb": "u", "\u00fc": "u", "\u00fd": "y", "\u00ff": "y",
    "\u015b": "s", "\u017a": "z", "\u017c": "z", "\u0107": "c", "\u010d": "c", "\u0161": "s",
}

# Leet-speak fold used ONLY for the skeleton view (rule matching on obfuscated text).
LEET = {
    "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
    "$": "s", "@": "a", "|": "l", "+": "t", "\u00a7": "s",
}

_TOKEN_RE = re.compile(
    r"[a-z]+"
    r"|[0-9]+"
    r"|[\u0900-\u097f]+"
    r"|[\u0980-\u09ff]+"
    r"|[\u0a00-\u0a7f]+"
    r"|[\u0b80-\u0bff]+"
    r"|[\u0c00-\u0c7f]+"
    r"|[\u0600-\u06ff]+"
    r"|[\u0e00-\u0e7f]+"
)

_WS_RE = re.compile(r"\s+")


def strip_invisibles(text: str) -> str:
    out = []
    for ch in text:
        if ch in _ZERO_WIDTH:
            continue
        out.append(" " if ch in _SPACE_LIKE else ch)
    return "".join(out)


def fold_glyphs(text: str) -> str:
    """Lowercase + confusable/diacritic folding."""
    out = []
    for ch in text:
        low = ch.lower() if ch != "\u0130" else "i"
        if low in HOMOGLYPHS:
            out.append(HOMOGLYPHS[low])
        elif low in DIACRITICS:
            out.append(DIACRITICS[low])
        else:
            out.append(low)
    return "".join(out)


def normalize(text: str) -> str:
    """Canonical normalized view used by rules, ML features and URLs."""
    if not text:
        return ""
    return _WS_RE.sub(" ", fold_glyphs(strip_invisibles(text))).strip()


def skeleton(text: str) -> str:
    """Normalized view with leet substitutions, for obfuscation-tolerant rules."""
    clean = normalize(text)
    return "".join(LEET.get(ch, ch) for ch in clean)


def tokenize(clean: str) -> list[str]:
    """Token list; every digit run collapses to the single token "num"."""
    toks = _TOKEN_RE.findall(clean)
    return ["num" if t[0].isdigit() else t for t in toks]


# ---------------------------------------------------------------------------
# Features
# ---------------------------------------------------------------------------

_URL_RE = re.compile(r"(?:https?://|www\.)[^\s]+")
_SHORTENER_HINTS = (
    "bit.ly", "tinyurl", "goo.gl", "t.co", "ow.ly", "is.gd", "buff.ly",
    "cutt.ly", "rb.gy", "rebrand.ly", "shorturl", "tiny.cc", "surl.li",
)
_PHONE_RE = re.compile(r"(?:\+\d[\d\-\s]{7,}\d)|(?:\b[6-9]\d{9}\b)")
_EMAIL_RE = re.compile(r"[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}")
_UPI_RE = re.compile(r"\b[a-z0-9.\-_]{2,}@(?:okaxis|oksbi|okhdfcbank|okicici|ybl|paytm|apl|upi|ibl|axl|axisb)")
_MONEY_RE = re.compile(r"(?:rs\.?|inr|₹|\$|usd|eur|pounds?)\s?[0-9]")
_OFFER_RE = re.compile(r"(?:[0-9]{1,3}\s?%\s?(?:off|discount|cashback|reward)|up\s?to\s?[0-9])")


def message_flags(text: str, clean: str) -> list[str]:
    flags: list[str] = []
    # ASCII-only, to match the Dart mirror exactly (non-Latin scripts skip this).
    letters = sum(1 for c in text if "a" <= c <= "z" or "A" <= c <= "Z")
    upper = sum(1 for c in text if "A" <= c <= "Z")
    if letters >= 6 and upper / max(letters, 1) > 0.4:
        flags.append("caps_heavy")
    if text.count("!") >= 2:
        flags.append("exclam2")
    if text.count("?") >= 2:
        flags.append("question2")
    if len(clean) >= 160:
        flags.append("long")
    if _URL_RE.search(clean):
        flags.append("has_url")
    if any(h in clean for h in _SHORTENER_HINTS):
        flags.append("url_shortener")
    if _PHONE_RE.search(clean):
        flags.append("has_phone")
    if _EMAIL_RE.search(clean):
        flags.append("has_email")
    if _UPI_RE.search(clean):
        flags.append("has_upi")
    if _MONEY_RE.search(clean):
        flags.append("has_money")
    if _OFFER_RE.search(clean):
        flags.append("has_offer_pct")
    has_deva = any("\u0900" <= c <= "\u097f" for c in clean)
    has_other_script = any(
        "\u0980" <= c <= "\u0c7f" or "\u0600" <= c <= "\u06ff" or "\u0e00" <= c <= "\u0e7f"
        for c in clean
    )
    has_ascii_alpha = any("a" <= c <= "z" for c in clean)
    if has_deva:
        flags.append("script_devanagari")
    if has_other_script:
        flags.append("script_other")
    if (has_deva or has_other_script) and has_ascii_alpha:
        flags.append("mixed_script")
    digit_runs = sum(1 for t in _TOKEN_RE.findall(clean) if t[0].isdigit())
    if digit_runs >= 2:
        flags.append("num_runs2")
    return flags


def _token_features(toks: list[str], feats: set[str], uni: str, bi: str, ch: str) -> None:
    for t in toks:
        feats.add(uni + t)
    for a, b in zip(toks, toks[1:]):
        feats.add(bi + a + "_" + b)

    grams = 0
    qualifying = 0
    for t in toks:
        if len(t) < 5 or grams >= 240:
            continue
        qualifying += 1
        if qualifying > 12:
            break
        for i in range(len(t) - 3):
            feats.add(ch + t[i:i + 4])
            grams += 1
            if grams >= 240:
                break


def featurize(text: str) -> list[str]:
    """Deterministic, de-duplicated feature strings for one raw message."""
    clean = normalize(text)
    skel = skeleton(text)
    feats: set[str] = set()

    _token_features(tokenize(clean), feats, "u:", "b:", "c:")
    if skel != clean:
        _token_features(tokenize(skel), feats, "su:", "sb:", "sc:")

    for f in message_flags(text, clean):
        feats.add("f:" + f)

    return sorted(feats)


# ---------------------------------------------------------------------------
# Hashing
# ---------------------------------------------------------------------------

def fnv1a32(value: str) -> int:
    """FNV-1a 32-bit over UTF-8 bytes (unsigned, wraps at 2**32)."""
    h = 0x811C9DC5
    for byte in value.encode("utf-8"):
        h ^= byte
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def hashed_index(feature: str, buckets: int = DEFAULT_BUCKETS) -> tuple[int, int]:
    h = fnv1a32(feature)
    return h % buckets, (-1 if (h >> 31) & 1 else 1)


def vector(text: str, buckets: int = DEFAULT_BUCKETS) -> dict[int, float]:
    """Signed hashing trick: colliding features accumulate (identical in Dart)."""
    vec: dict[int, float] = {}
    for feat in featurize(text):
        bucket, sign = hashed_index(feat, buckets)
        vec[bucket] = vec.get(bucket, 0.0) + float(sign)
    return vec
