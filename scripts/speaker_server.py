"""Local, persistent speaker-verification service for Aegis."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path

import numpy as np
import librosa
import joblib
from resemblyzer import VoiceEncoder, preprocess_wav

ROOT = Path(__file__).resolve().parent.parent
PROFILE = np.load(ROOT / ".aegis/voices/my-speaker-profile.npy")
WAKE_TEMPLATES = np.load(ROOT / ".aegis/voices/aegis-wakeword-profile.npz")["templates"]
WAKE_MODEL_PATH = ROOT / ".aegis/voices/aegis-wakeword-model.joblib"
WAKE_MODEL = joblib.load(WAKE_MODEL_PATH) if WAKE_MODEL_PATH.exists() else None
ENCODER = VoiceEncoder()


class Handler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:
        if self.path not in {"/verify", "/wake"}:
            self.send_error(404)
            return
        try:
            length = int(self.headers["Content-Length"])
            audio = Path(json.loads(self.rfile.read(length))["audio"])
            if self.path == "/wake":
                waveform, sample_rate = librosa.load(audio, sr=16_000, mono=True)
                mfcc = librosa.feature.mfcc(y=waveform, sr=sample_rate, n_mfcc=20, hop_length=160)
                mfcc = librosa.util.fix_length(mfcc, size=100, axis=1).astype(np.float32).reshape(-1)
                if WAKE_MODEL is not None:
                    score = float(WAKE_MODEL.predict_proba(mfcc.reshape(1, -1))[0, 1])
                else:
                    templates = WAKE_TEMPLATES.reshape(len(WAKE_TEMPLATES), -1)
                    score = float(np.max(templates @ mfcc / (np.linalg.norm(templates, axis=1) * np.linalg.norm(mfcc) + 1e-8)))
            else:
                embedding = ENCODER.embed_utterance(preprocess_wav(audio))
                score = float(np.dot(embedding, PROFILE) / (np.linalg.norm(embedding) * np.linalg.norm(PROFILE)))
            body = json.dumps({"score": score}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception as error:
            self.send_error(500, str(error))

    def log_message(self, *_: object) -> None:
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 4319), Handler).serve_forever()
