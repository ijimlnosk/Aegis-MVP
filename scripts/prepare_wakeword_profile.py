"""Create an audio wake-word profile from a recording of repeated calls."""

from pathlib import Path

import librosa
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "src/assets/voices/aegis.mp3"
OUTPUT = ROOT / ".aegis/voices/aegis-wakeword-profile.npz"


def feature(audio: np.ndarray, sample_rate: int) -> np.ndarray:
    mfcc = librosa.feature.mfcc(y=audio, sr=sample_rate, n_mfcc=20, hop_length=160)
    return librosa.util.fix_length(mfcc, size=100, axis=1).astype(np.float32)


def main() -> None:
    audio, sample_rate = librosa.load(SOURCE, sr=16_000, mono=True)
    intervals = librosa.effects.split(audio, top_db=28, frame_length=1024, hop_length=256)
    samples = [audio[start:end] for start, end in intervals if 0.25 <= (end - start) / sample_rate <= 2.0]
    if len(samples) < 5:
        raise SystemExit("호출어 구간을 5개 이상 찾지 못했습니다. 녹음에 짧은 무음 구간을 넣어 주세요.")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(OUTPUT, templates=np.stack([feature(item, sample_rate) for item in samples]))
    print(f"saved {len(samples)} wake-word samples to {OUTPUT}")


if __name__ == "__main__":
    main()
