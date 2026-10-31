# SIRIUS voice server: Silero TTS (the same voices as desktop SIRIUS) for the speaker Worker.
# POST /tts {"text", "speaker", "rate"} with header "Authorization: Bearer <TTS_KEY>"
# -> raw 16 kHz 16-bit mono PCM.
import os
import re

import torch
from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

torch.set_num_threads(int(os.environ.get("THREADS", "1")))
MODEL_URL = "https://models.silero.ai/models/tts/ru/v5_5_ru.pt"
MODEL_PATH = os.environ.get("MODEL_PATH", "/app/v5_5_ru.pt")
if not os.path.exists(MODEL_PATH):
    torch.hub.download_url_to_file(MODEL_URL, MODEL_PATH)
model = torch.package.PackageImporter(MODEL_PATH).load_pickle("tts_models", "model")
SPEAKERS = {"aidar", "eugene", "baya", "kseniya", "xenia"}
KEY = os.environ.get("TTS_KEY", "")

app = FastAPI()


class Req(BaseModel):
    text: str
    speaker: str = "aidar"
    rate: float = 1.0  # 0.7..1.4, speech speed


def chunks(text: str, limit: int = 800):
    # Silero handles up to ~1000 characters per call: split on sentence ends.
    parts, cur = [], ""
    for sentence in re.split(r"(?<=[.!?…])\s+", text):
        if len(cur) + len(sentence) > limit and cur:
            parts.append(cur)
            cur = ""
        cur = f"{cur} {sentence}".strip()
    if cur:
        parts.append(cur)
    return parts


@app.get("/")
def health():
    return {"ok": True, "speakers": sorted(SPEAKERS)}


@app.post("/tts")
def tts(req: Req, authorization: str = Header(default="")):
    if KEY and authorization != f"Bearer {KEY}":
        raise HTTPException(401, "bad key")
    speaker = req.speaker if req.speaker in SPEAKERS else "aidar"
    audio = []
    for part in chunks(req.text.strip()[:3000]):
        try:
            a = model.apply_tts(text=part, speaker=speaker, sample_rate=48000, put_accent=True, put_yo=True)
        except Exception:
            continue  # text without speakable characters
        # Speed change by resampling in time, then 48 kHz -> 16 kHz.
        rate = min(max(req.rate, 0.7), 1.4)
        target = int(len(a) / rate / 3)
        a = torch.nn.functional.interpolate(a[None, None], size=target, mode="linear")[0, 0]
        audio.append(a)
        audio.append(torch.zeros(2400))  # 150 ms pause between parts
    if not audio:
        return Response(b"", media_type="audio/L16; rate=16000")
    pcm = (torch.cat(audio).clamp(-1, 1) * 32767).to(torch.int16).numpy().tobytes()
    return Response(pcm, media_type="audio/L16; rate=16000")
