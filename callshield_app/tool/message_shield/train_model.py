"""Train the Message Shield on-device classifier (reference pipeline).

Model: multinomial logistic regression (softmax) over the hashed feature space
defined in features.py. Roughly 4096 buckets x 10 classes = 41k parameters,
quantised to int8 -- about 41 KB on disk, pure CPU, no GPU, no cloud, runs on
low-end Android phones.

Usage:
    python tool/message_shield/dataset_generator.py
    python tool/message_shield/train_model.py

Outputs:
    assets/message_shield/ml/message_shield_model.json   (shipped weights)
    tool/message_shield/data/report.json                 (measured metrics)

Optional extra data: put files named *.jsonl or *.txt in
tool/message_shield/data/external/ with lines "label<TAB>text" to merge an open
corpus you obtained yourself (see README.md for provenance notes).
"""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path

import numpy as np

from dataset_generator import CLASSES
from features import DEFAULT_BUCKETS, FEATURE_VERSION, vector

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]                      # callshield_app/
DATA_DIR = HERE / "data"
MODEL_ASSET = ROOT / "assets" / "message_shield" / "ml" / "message_shield_model.json"
REPORT = DATA_DIR / "report.json"
CLASS_INDEX = {name: i for i, name in enumerate(CLASSES)}


# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

def load_jsonl(path: Path) -> list[dict]:
    rows: list[dict] = []
    if not path.exists():
        raise FileNotFoundError(f"missing {path}; run dataset_generator.py first")
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def load_external() -> list[dict]:
    ext_dir = DATA_DIR / "external"
    rows: list[dict] = []
    if not ext_dir.exists():
        return rows
    for path in sorted(ext_dir.glob("*")):
        if path.suffix not in (".txt", ".jsonl", ".tsv"):
            continue
        with path.open(encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line.strip():
                    continue
                if path.suffix == ".jsonl":
                    row = json.loads(line)
                    label = row["label"]
                    text = row["text"]
                else:
                    label, _, text = line.partition("\t")
                if label.strip() not in CLASS_INDEX:
                    continue
                rows.append({"text": text, "label": label.strip(), "source": path.name})
        print(f"merged external data: {path.name} ({len(rows)} rows so far)")
    return rows


def build_matrices(rows: list[dict], buckets: int) -> tuple[np.ndarray, np.ndarray]:
    x = np.zeros((len(rows), buckets), dtype=np.float32)
    y = np.zeros(len(rows), dtype=np.int64)
    for i, row in enumerate(rows):
        for bucket, value in vector(row["text"], buckets).items():
            x[i, bucket] = value
        y[i] = CLASS_INDEX[row["label"]]
    return x, y


# ---------------------------------------------------------------------------
# Training
# ---------------------------------------------------------------------------

def softmax(logits: np.ndarray) -> np.ndarray:
    logits = logits - logits.max(axis=1, keepdims=True)
    exp = np.exp(logits)
    return exp / exp.sum(axis=1, keepdims=True)


def class_weights(y: np.ndarray, n_classes: int) -> np.ndarray:
    counts = np.bincount(y, minlength=n_classes).astype(np.float64)
    counts[counts == 0] = 1
    w = counts.sum() / (n_classes * counts)
    return w


def train(
    x_train: np.ndarray,
    y_train: np.ndarray,
    x_val: np.ndarray,
    y_val: np.ndarray,
    n_classes: int,
    seed: int,
    epochs: int = 200,
    lr: float = 0.5,
    l2: float = 1e-4,
    feature_dropout: float = 0.10,
    batch: int = 256,
) -> tuple[np.ndarray, np.ndarray, dict]:
    """Adagrad on the softmax objective.

    Adagrad (rather than Adam) because the hashed feature vectors are very
    sparse: Adam's exponential second-moment estimate decays to near zero for
    rarely-updated coordinates and then produces vanishing steps. Adagrad's
    monotonically accumulating denominator keeps sparse coordinates moving.
    """
    rng = np.random.default_rng(seed)
    n_features = x_train.shape[1]
    w = np.zeros((n_classes, n_features), dtype=np.float64)
    b = np.zeros(n_classes, dtype=np.float64)

    acc_w = np.full_like(w, 1e-8)
    acc_b = np.full_like(b, 1e-8)
    eps = 1e-8

    cw = class_weights(y_train, n_classes)
    sample_w = cw[y_train]
    best = (-1.0, None, None, 0)
    history: list[dict] = []

    for epoch in range(1, epochs + 1):
        order = rng.permutation(len(x_train))
        for start in range(0, len(order), batch):
            idx = order[start:start + batch]
            xb, yb, wb = x_train[idx], y_train[idx], sample_w[idx]
            if feature_dropout > 0:
                # Feature dropout keeps the model from memorising exact phrases
                # from the training templates (helps on unseen wording).
                mask = (rng.random(xb.shape) > feature_dropout).astype(np.float32)
                xb = xb * mask
            logits = xb @ w.T + b
            probs = softmax(logits)
            probs[np.arange(len(yb)), yb] -= 1.0
            probs *= wb[:, None]
            probs /= len(yb)
            g_w = probs.T @ xb + l2 * w
            g_b = probs.sum(axis=0) / len(yb)

            acc_w += g_w ** 2
            acc_b += g_b ** 2
            w -= lr * g_w / (np.sqrt(acc_w) + eps)
            b -= lr * g_b / (np.sqrt(acc_b) + eps)

        val_probs = softmax(x_val @ w.T + b)
        val_pred = val_probs.argmax(axis=1)
        macro_f1 = macro_f1_score(y_val, val_pred, n_classes)
        if epoch <= 5 or epoch % 10 == 0:
            history.append({"epoch": epoch, "val_macro_f1": round(float(macro_f1), 4)})
        if macro_f1 > best[0]:
            best = (macro_f1, w.copy(), b.copy(), epoch)
        if epoch - best[3] > 30:
            break

    return best[1], best[2], {
        "best_epoch": best[3],
        "val_macro_f1": round(float(best[0]), 4),
        "val_curve": history[:: max(1, len(history) // 12)] + [history[-1]],
    }


def confusion(y_true: np.ndarray, y_pred: np.ndarray, n_classes: int) -> np.ndarray:
    cm = np.zeros((n_classes, n_classes), dtype=np.int64)
    for t, p in zip(y_true, y_pred):
        cm[t, p] += 1
    return cm


def macro_f1_score(y_true: np.ndarray, y_pred: np.ndarray, n_classes: int) -> float:
    cm = confusion(y_true, y_pred, n_classes)
    f1s = []
    for c in range(n_classes):
        tp = cm[c, c]
        fp = cm[:, c].sum() - tp
        fn = cm[c, :].sum() - tp
        precision = tp / (tp + fp) if tp + fp else 0.0
        recall = tp / (tp + fn) if tp + fn else 0.0
        f1s.append(0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall))
    return float(np.mean(f1s))


def report_metrics(y_true: np.ndarray, y_pred: np.ndarray, n_classes: int) -> dict:
    cm = confusion(y_true, y_pred, n_classes)
    total = int(cm.sum())
    correct = int(np.trace(cm))
    per_class = {}
    f1s = []
    for c, name in enumerate(CLASSES):
        tp = int(cm[c, c])
        fp = int(cm[:, c].sum() - tp)
        fn = int(cm[c, :].sum() - tp)
        precision = tp / (tp + fp) if tp + fp else 0.0
        recall = tp / (tp + fn) if tp + fn else 0.0
        f1 = 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)
        f1s.append(f1)
        per_class[name] = {
            "support": int(cm[c, :].sum()),
            "precision": round(precision, 4),
            "recall": round(recall, 4),
            "f1": round(f1, 4),
        }
    legit = CLASS_INDEX["legitimate"]
    legit_total = int(cm[legit, :].sum())
    legit_fp = legit_total - int(cm[legit, legit])
    scam_preds = int(cm[:, legit].sum() - cm[legit, legit])
    return {
        "samples": total,
        "accuracy": round(correct / total, 4) if total else 0.0,
        "macro_f1": round(float(np.mean(f1s)), 4),
        "legitimate_false_positive_rate": round(legit_fp / legit_total, 4) if legit_total else 0.0,
        "legitimate_recall": round(float(cm[legit, legit] / legit_total), 4) if legit_total else 0.0,
        "scam_messages_misclassified_as_legitimate": scam_preds,
        "per_class": per_class,
        "confusion_matrix": cm.tolist(),
    }


# ---------------------------------------------------------------------------
# Quantisation
# ---------------------------------------------------------------------------

def quantise_int8(w: np.ndarray) -> tuple[np.ndarray, float]:
    scale = float(np.abs(w).max() / 127.0) or 1.0
    q = np.clip(np.round(w / scale), -127, 127).astype(np.int8)
    return q, scale


def dequantised_predict(x: np.ndarray, q: np.ndarray, scale: float, b: np.ndarray, classes: int, buckets: int) -> np.ndarray:
    w = q.astype(np.float32).reshape(classes, buckets) * scale
    return (x @ w.T + b).argmax(axis=1)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def binary_metrics(y_true: np.ndarray, y_pred: np.ndarray, legit_index: int) -> dict:
    """Operational view: legitimate vs (spam or scam)."""
    true_bin = (y_true != legit_index).astype(np.int64)
    pred_bin = (y_pred != legit_index).astype(np.int64)
    tp = int(((pred_bin == 1) & (true_bin == 1)).sum())
    fp = int(((pred_bin == 1) & (true_bin == 0)).sum())
    fn = int(((pred_bin == 0) & (true_bin == 1)).sum())
    tn = int(((pred_bin == 0) & (true_bin == 0)).sum())
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    return {
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "f1": round(0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall), 4),
        "false_positive_rate_on_legitimate": round(fp / (fp + tn), 4) if fp + tn else 0.0,
        "true_negatives": tn,
        "false_positives": fp,
        "false_negatives": fn,
        "true_positives": tp,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--buckets", type=int, default=DEFAULT_BUCKETS)
    args = parser.parse_args()

    train_rows = load_jsonl(DATA_DIR / "train.jsonl")
    val_rows = load_jsonl(DATA_DIR / "val.jsonl")
    corpus_path = ROOT / "assets" / "message_shield" / "eval" / "held_out_corpus.json"
    test_rows = json.loads(corpus_path.read_text(encoding="utf-8"))["samples"]
    train_rows += load_external()

    print(f"train={len(train_rows)} val={len(val_rows)} test={len(test_rows)}")
    x_train, y_train = build_matrices(train_rows, args.buckets)
    x_val, y_val = build_matrices(val_rows, args.buckets)
    x_test, y_test = build_matrices(test_rows, args.buckets)

    w, b, train_info = train(x_train, y_train, x_val, y_val, len(CLASSES), args.seed)
    float_pred = (x_test @ w.T + b).argmax(axis=1)
    float_metrics = report_metrics(y_test, float_pred, len(CLASSES))

    q, scale = quantise_int8(w)
    q_pred = dequantised_predict(x_test, q, scale, b.astype(np.float32), len(CLASSES), args.buckets)
    q_metrics = report_metrics(y_test, q_pred, len(CLASSES))

    legit_index = CLASS_INDEX["legitimate"]
    adv_idx = np.array([bool(row.get("adversarial")) for row in test_rows])
    plain_idx = ~adv_idx

    q_binary = binary_metrics(y_test, q_pred, legit_index)
    q_binary_adv = binary_metrics(y_test[adv_idx], q_pred[adv_idx], legit_index) if adv_idx.any() else {}
    q_binary_plain = binary_metrics(y_test[plain_idx], q_pred[plain_idx], legit_index) if plain_idx.any() else {}
    q_adv_macro = (
        macro_f1_score(y_test[adv_idx], q_pred[adv_idx], len(CLASSES)) if adv_idx.any() else 0.0
    )

    print(f"quantised int8 macro-F1 on held-out test: {macro_f1_score(y_test, q_pred, len(CLASSES)):.4f}")
    print(f"quantised accuracy: {q_metrics['accuracy']:.4f}  legit FPR: {q_metrics['legitimate_false_positive_rate']:.4f}")
    print(f"binary scam/spam detection: {q_binary}")
    print(f"binary (obfuscated slice, n={int(adv_idx.sum())}): {q_binary_adv}")
    print(f"10-class macro-F1 on obfuscated slice: {q_adv_macro:.4f}")

    payload = {
        "version": 1,
        "format": "hashed-linear-softmax-int8",
        "feature_version": FEATURE_VERSION,
        "buckets": args.buckets,
        "classes": CLASSES,
        "quantization_scale": scale,
        "weights_b64": base64.b64encode(q.tobytes()).decode("ascii"),
        "bias": [round(float(v), 5) for v in b],
        "training": {
            "generator": "tool/message_shield/train_model.py",
            "seed": args.seed,
            "model": "multinomial logistic regression (softmax) over hashed n-grams",
            "train_samples": len(train_rows),
            "val_samples": len(val_rows),
            "test_samples": len(test_rows),
            "split_policy": "template-disjoint train/val/test",
            "inference": "pure CPU, sparse dot product, no GPU, fully offline",
            **train_info,
        },
        "metrics": {
            "held_out_test_quantised_int8": q_metrics,
            "held_out_test_float32": float_metrics,
            "held_out_binary_scam_vs_legit": q_binary,
            "held_out_binary_obfuscated_slice": q_binary_adv,
            "held_out_binary_plain_slice": q_binary_plain,
            "held_out_macro_f1_obfuscated_slice": round(float(q_adv_macro), 4),
            "honesty_note": (
                "Metrics are measured on a synthetic held-out set that shares its "
                "component vocabulary with training, so they are optimistic about "
                "real-world accuracy. Treat the ML output as one weighted signal "
                "inside the risk engine, not as a standalone verdict."
            ),
        },
    }

    MODEL_ASSET.parent.mkdir(parents=True, exist_ok=True)
    MODEL_ASSET.write_text(json.dumps(payload), encoding="utf-8")
    size_kb = MODEL_ASSET.stat().st_size / 1024
    print(f"model asset written: {MODEL_ASSET} ({size_kb:.1f} KB)")

    REPORT.write_text(json.dumps({"train": train_info, "test": q_metrics}, indent=1), encoding="utf-8")
    print(f"report written: {REPORT}")


if __name__ == "__main__":
    main()
