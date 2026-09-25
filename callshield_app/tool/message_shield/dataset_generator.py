"""Message Shield synthetic dataset generator (deterministic, seeded).

Usage:
    python tool/message_shield/dataset_generator.py            # default seed 1337
    python tool/message_shield/dataset_generator.py --seed 7

Outputs
-------
tool/message_shield/data/train.jsonl               training split
tool/message_shield/data/val.jsonl                 validation split
assets/message_shield/eval/held_out_corpus.json    SHIPPED held-out test set

Two sources of messages are combined:
  1. authored templates (templates.py) expanded with slot sampling
  2. compositional messages (fragments.py): opener + core + optional pressure
     + optional close

Both are split so that no template or fragment is shared between splits: the
validation and test sets are built only from wording that training never saw,
which keeps the reported numbers honest instead of measuring memorisation.
Everything is authored for this repository, so no third-party corpus license
applies. See README.md for how to merge an open dataset you obtained yourself.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
from pathlib import Path

import fragments as F
from templates import ADVERSARIAL_TEMPLATES, SLOT_VALUES, TEMPLATES

ROOT = Path(__file__).resolve().parents[2]          # callshield_app/
DATA_DIR = Path(__file__).resolve().parent / "data"
EVAL_ASSET = ROOT / "assets" / "message_shield" / "eval" / "held_out_corpus.json"

CLASSES = [
    "legitimate",
    "spam",
    "phishing",
    "financial_fraud",
    "credential_theft",
    "impersonation",
    "social_engineering",
    "investment_scam",
    "reward_scam",
    "delivery_scam",
]

PLACEHOLDER_RE = re.compile(r"\{([a-z0-9_]+)\}")

# per-class targets, distributed over whatever fragments/templates a split owns
COMPOSITIONAL_TARGETS = {"train": 900, "val": 260, "test": 70}
TEMPLATE_TARGETS = {"train": 400, "val": 0, "test": 0}

LEET_FWD = {"a": "4", "e": "3", "o": "0", "i": "1", "s": "5", "t": "7"}
HOMOGLYPH_FWD = {"a": "\u0430", "e": "\u0435", "o": "\u043e", "p": "\u0440", "c": "\u0441", "x": "\u0445"}
FILLERS = ["sir ", "dear ", "kindly ", "plz ", "please ", "respected sir "]


def stable_bucket(text: str, mod: int) -> int:
    digest = hashlib.sha1(text.encode("utf-8")).hexdigest()[:8]
    return int(digest, 16) % mod


def template_split(template: str) -> str:
    """Template-level split assignment (no template crosses splits)."""
    b = stable_bucket("split:" + template, 5)
    if b == 0:
        return "test"
    if b == 1:
        return "val"
    return "train"


def fragment_split(fragment: str) -> str:
    """Fragment-level split: 70% train / 15% val / 15% eval-only wording.

    Evaluation messages are still built from wording training never sees, but
    training keeps most of the class vocabulary so the model is not starved.
    """
    b = stable_bucket("frag:" + fragment, 20)
    if b < 14:
        return "train"
    if b < 17:
        return "val"
    return "test"


def fill(template: str, rng: random.Random) -> str:
    def repl(match: re.Match) -> str:
        return rng.choice(SLOT_VALUES[match.group(1)])

    return PLACEHOLDER_RE.sub(repl, template)


def compose(label: str, rng: random.Random) -> str:
    """Build one base message (slots still unfilled) from the role pools."""
    openers, cores, pressures, closes = (
        F.OPENERS[label],
        F.CORES[label],
        F.PRESSURES[label],
        F.CLOSES[label],
    )
    parts = [rng.choice(openers), rng.choice(cores)]
    if rng.random() < 0.8:
        parts.append(rng.choice(pressures))
    if rng.random() < 0.7:
        parts.append(rng.choice(closes))
    return " ".join(parts)


def augment(text: str, rng: random.Random, aggression: float) -> tuple[str, bool]:
    """Apply 0-2 obfuscation/augmentation transforms. Returns (text, adversarial)."""
    adversarial = False
    transforms = []
    if rng.random() < 0.35:
        transforms.append("case")
    if rng.random() < aggression:
        transforms.append("leet")
    if rng.random() < aggression * 0.5:
        transforms.append("homoglyph")
    if rng.random() < aggression * 0.5:
        transforms.append("spacing")
    if rng.random() < aggression * 0.3:
        transforms.append("zerowidth")
    if rng.random() < 0.4:
        transforms.append("punct")
    if rng.random() < 0.3:
        transforms.append("filler")

    rng.shuffle(transforms)
    transforms = transforms[: rng.choice([1, 1, 2])]

    for name in transforms:
        if name == "case":
            words = text.split(" ")
            for _ in range(rng.randint(1, 3)):
                i = rng.randrange(len(words))
                words[i] = words[i].upper()
            text = " ".join(words)
        elif name == "leet":
            chars = list(text)
            for _ in range(rng.randint(1, 3)):
                idxs = [i for i, c in enumerate(chars) if c in LEET_FWD]
                if not idxs:
                    break
                i = rng.choice(idxs)
                chars[i] = LEET_FWD[chars[i]]
            text = "".join(chars)
            adversarial = True
        elif name == "homoglyph":
            chars = list(text)
            for _ in range(rng.randint(1, 2)):
                idxs = [i for i, c in enumerate(chars) if c.lower() in HOMOGLYPH_FWD]
                if not idxs:
                    break
                i = rng.choice(idxs)
                chars[i] = HOMOGLYPH_FWD[chars[i].lower()]
            text = "".join(chars)
            adversarial = True
        elif name == "spacing":
            words = text.split(" ")
            idxs = [i for i, w in enumerate(words) if 2 <= len(w) <= 5 and w.isalpha()]
            if idxs:
                i = rng.choice(idxs)
                words[i] = " ".join(words[i])
                text = " ".join(words)
                adversarial = True
        elif name == "zerowidth":
            words = text.split(" ")
            idxs = [i for i, w in enumerate(words) if len(w) > 5]
            if idxs:
                i = rng.choice(idxs)
                w = words[i]
                pos = rng.randrange(1, len(w) - 1)
                words[i] = w[:pos] + "\u200b" + w[pos:]
                text = " ".join(words)
                adversarial = True
        elif name == "punct":
            text = text.rstrip(".") + rng.choice(["!!", "!!", " ...", " !"])
        elif name == "filler":
            text = rng.choice(FILLERS) + text[0].lower() + text[1:]

    return text, adversarial


def aggression_for(label: str) -> float:
    return 0.05 if label == "legitimate" else 0.30


def _emit(rows: list[dict], counter: int, text: str, label: str, adversarial: bool, source: str) -> int:
    text = " ".join(text.split())
    if not text:
        return counter
    counter += 1
    rows.append(
        {
            "id": "ms-%05d" % counter,
            "text": text,
            "label": label,
            "adversarial": bool(adversarial),
            "source": source,
        }
    )
    return counter


def build_corpus(seed: int) -> dict[str, list[dict]]:
    rng = random.Random(seed)
    splits: dict[str, list[dict]] = {"train": [], "val": [], "test": []}
    counter = 0

    # ---- 1. compositional messages ----------------------------------------
    # Base messages (unique fragment combinations) are assigned to a split by a
    # stable hash, so no base message crosses splits. Slots are sampled and
    # obfuscation applied afterwards, which is why the held-out set contains new
    # wordings built from the same component vocabulary.
    for label in CLASSES:
        bases: set[str] = set()
        attempts = 0
        while len(bases) < 600 and attempts < 20000:
            attempts += 1
            bases.add(compose(label, rng))
        grouped: dict[str, list[str]] = {"train": [], "val": [], "test": []}
        for base in sorted(bases):
            b = stable_bucket("base:" + base, 20)
            grouped["train" if b < 14 else ("val" if b < 17 else "test")].append(base)

        for split, target in COMPOSITIONAL_TARGETS.items():
            pool = grouped[split]
            if not pool:
                print(f"warning: {label}/{split} has no base messages")
                continue
            per_base = max(1, -(-target // len(pool)))
            made = 0
            for base in pool:
                for _ in range(per_base):
                    text, adv = augment(fill(base, rng), rng, aggression_for(label))
                    counter = _emit(splits[split], counter, text, label, adv, "compositional_fragments")
                    made += 1
            if made < target:
                print(f"warning: {label}/{split} produced {made}/{target} compositional samples")

    # ---- 2. authored templates (train only) -------------------------------
    for label, templates in TEMPLATES.items():
        train_templates = [t for t in templates if template_split(t) == "train"]
        if not train_templates:
            continue
        per_template = -(-TEMPLATE_TARGETS["train"] // len(train_templates))
        for tpl in train_templates:
            for _ in range(per_template):
                text, adv = augment(fill(tpl, rng), rng, aggression_for(label))
                counter = _emit(splits["train"], counter, text, label, adv, "authored_template")

    # ---- 3. authored obfuscation pool -> held-out test set only -----------
    for label, tpl in ADVERSARIAL_TEMPLATES:
        for _ in range(3):
            text, _ = augment(tpl, rng, 0.5)
            counter = _emit(splits["test"], counter, text, label, True, "authored_adversarial")

    for split in splits:
        rng.shuffle(splits[split])
    return splits


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=1337)
    args = parser.parse_args()

    splits = build_corpus(args.seed)

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    for split in ("train", "val"):
        path = DATA_DIR / f"{split}.jsonl"
        with path.open("w", encoding="utf-8") as fh:
            for row in splits[split]:
                fh.write(json.dumps(row, ensure_ascii=False) + "\n")
        print(f"{split}: {len(splits[split])} messages -> {path}")

    EVAL_ASSET.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "version": 1,
        "generator": "tool/message_shield/dataset_generator.py",
        "seed": args.seed,
        "classes": CLASSES,
        "note": (
            "Held-out synthetic test set. No base message, authored template or "
            "obfuscation pool entry from training appears here: the test split "
            "contains new wordings and new slot fills. Component vocabulary "
            "overlaps with training. Authored for this repository; no "
            "third-party corpus is redistributed. Metrics measured on this set "
            "describe this distribution and are NOT a claim about real-world "
            "accuracy."
        ),
        "samples": splits["test"],
    }
    EVAL_ASSET.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"test: {len(splits['test'])} messages -> {EVAL_ASSET}")

    counts: dict[str, dict[str, int]] = {}
    for split, rows in splits.items():
        per_class: dict[str, int] = {}
        for row in rows:
            per_class[row["label"]] = per_class.get(row["label"], 0) + 1
        counts[split] = per_class
    print(json.dumps(counts, indent=1))
    adv = sum(1 for row in splits["test"] if row["adversarial"])
    print(f"adversarial share of test set: {adv}/{len(splits['test'])}")


if __name__ == "__main__":
    main()
