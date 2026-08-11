"""Create a local speaker embedding from a reference recording."""

from argparse import ArgumentParser
from pathlib import Path

import numpy as np
from resemblyzer import VoiceEncoder, preprocess_wav


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    wav = preprocess_wav(args.input)
    if len(wav) < 16_000 * 10:
        raise SystemExit("기준 음성은 10초 이상 필요합니다.")

    embedding = VoiceEncoder().embed_utterance(wav)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    np.save(args.output, embedding)
    print(f"저장 완료: {args.output} ({len(wav) / 16_000:.1f}초)")


if __name__ == "__main__":
    main()
