# SIRIUS voice server: Piper neural TTS (Russian voices) for the speaker Worker.
# Piper (ONNX) fits in a free 512 MB server, unlike Silero (PyTorch).
# POST /tts {"text", "speaker", "rate"} with header "Authorization: Bearer <TTS_KEY>"
# -> raw 16 kHz 16-bit mono PCM.
import os

import numpy as np
from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import Response
from piper import PiperVoice, SynthesisConfig
from pydantic import BaseModel

VOICE_DIR = os.environ.get("VOICE_DIR", "/app/voices")
SPEAKERS = ["dmitri", "denis", "ruslan", "irina"]
voices = {name: PiperVoice.load(f"{VOICE_DIR}/ru_RU-{name}-medium.onnx") for name in SPEAKERS}
KEY = os.environ.get("TTS_KEY", "")

app = FastAPI()


class Req(BaseModel):
    text: str
    speaker: str = "dmitri"
    rate: float = 1.0  # 0.7..1.4, speech speed


@app.get("/")
def health():
    return {"ok": True, "speakers": SPEAKERS}


@app.post("/tts")
def tts(req: Req, authorization: str = Header(default="")):
    if KEY and authorization != f"Bearer {KEY}":
        raise HTTPException(401, "bad key")
    voice = voices.get(req.speaker, voices["dmitri"])
    rate = min(max(req.rate, 0.7), 1.4)
    config = SynthesisConfig(length_scale=1.0 / rate)
    parts = []
    sample_rate = voice.config.sample_rate
    try:
        for chunk in voice.synthesize(req.text.strip()[:3000], syn_config=config):
            parts.append(np.frombuffer(chunk.audio_int16_bytes, dtype=np.int16))
            sample_rate = chunk.sample_rate
    except Exception as exc:
        print(f"synthesis failed: {exc!r}", flush=True)
    if not parts:
        return Response(b"", media_type="audio/L16; rate=16000")
    audio = np.concatenate(parts).astype(np.float32)
    # Resample to the speaker's 16 kHz bus.
    n = int(len(audio) * 16000 / sample_rate)
    audio = np.interp(np.linspace(0, len(audio) - 1, n), np.arange(len(audio)), audio)
    return Response(audio.astype(np.int16).tobytes(), media_type="audio/L16; rate=16000")
