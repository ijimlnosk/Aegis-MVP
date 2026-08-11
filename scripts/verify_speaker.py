"""Compare an audio clip with Aegis's locally stored speaker profile."""

from argparse import ArgumentParser

import numpy as np
from resemblyzer import VoiceEncoder, preprocess_wav


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("audio")
    parser.add_argument("profile")
    args = parser.parse_args()

    embedding = VoiceEncoder().embed_utterance(preprocess_wav(args.audio))
    profile = np.load(args.profile)
    score = float(np.dot(embedding, profile) / (np.linalg.norm(embedding) * np.linalg.norm(profile)))
    print(f"{score:.4f}")


if __name__ == "__main__":
    main()
