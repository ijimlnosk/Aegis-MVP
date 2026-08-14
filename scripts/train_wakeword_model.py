"""Train a personal wake-word classifier from Aegis' local SQLite dataset."""

import sqlite3
from pathlib import Path

import joblib
import librosa
import numpy as np
from sklearn.linear_model import LogisticRegression

ROOT = Path(__file__).resolve().parent.parent
DATABASE = Path.home() / "Library/Application Support/Aegis/learning.sqlite"
OUTPUT = ROOT / ".aegis/voices/aegis-wakeword-model.joblib"


def features(path: str) -> np.ndarray:
    audio, rate = librosa.load(path, sr=16_000, mono=True)
    mfcc = librosa.feature.mfcc(y=audio, sr=rate, n_mfcc=20, hop_length=160)
    return librosa.util.fix_length(mfcc, size=100, axis=1).reshape(-1)


def main() -> None:
    rows = sqlite3.connect(DATABASE).execute("SELECT path, label FROM wake_samples").fetchall()
    usable = [(path, label) for path, label in rows if Path(path).exists()]
    labels = [label for _, label in usable]
    if labels.count("wake") < 5 or labels.count("non_wake") < 5:
        raise SystemExit("wake와 non_wake 샘플을 각각 최소 5개씩 수집해 주세요.")
    matrix = np.stack([features(path) for path, _ in usable])
    targets = np.array([label == "wake" for _, label in usable])
    model = LogisticRegression(max_iter=2_000, class_weight="balanced").fit(matrix, targets)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(model, OUTPUT)
    print(f"trained {len(usable)} samples and saved {OUTPUT}")


if __name__ == "__main__":
    main()
