# SIRIUS voice server: Piper neural TTS (Russian voices) for the speaker Worker.
# Piper (ONNX) fits in a free 512 MB server, unlike Silero (PyTorch).
# POST /tts {"text", "speaker", "rate"} with header "Authorization: Bearer <TTS_KEY>"
# -> raw 16 kHz 16-bit mono PCM.
#
# It also relays /v1/* to the SIRIUS Worker: in Russia Cloudflare is throttled, so speakers
# that cannot reach panel.jarvishost.dpdns.org directly come in through this server.
import os

import httpx

import numpy as np
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import Response, StreamingResponse
from piper import PiperVoice, SynthesisConfig
from pydantic import BaseModel
from starlette.background import BackgroundTask

VOICE_DIR = os.environ.get("VOICE_DIR", "/app/voices")
SPEAKERS = ["dmitri", "denis", "ruslan", "irina"]
voices = {name: PiperVoice.load(f"{VOICE_DIR}/ru_RU-{name}-medium.onnx") for name in SPEAKERS}
KEY = os.environ.get("TTS_KEY", "")

app = FastAPI()
UPSTREAM = os.environ.get("RELAY_UPSTREAM", "https://panel.jarvishost.dpdns.org")
HOP = {"host", "connection", "transfer-encoding", "content-length", "keep-alive", "accept-encoding"}
relay_client = httpx.AsyncClient(timeout=httpx.Timeout(120, connect=15))


@app.api_route("/v1/{path:path}", methods=["GET", "POST", "OPTIONS"])
async def relay(path: str, request: Request):
    """Streams the request to the Worker and its reply back, byte for byte."""
    headers = {k: v for k, v in request.headers.items() if k.lower() not in HOP}
    body = await request.body()
    upstream = relay_client.build_request(request.method, f"{UPSTREAM}/v1/{path}", params=request.query_params,
                                          headers=headers, content=body)
    resp = await relay_client.send(upstream, stream=True)
    out = {k: v for k, v in resp.headers.items() if k.lower() not in HOP | {"content-encoding"}}
    return StreamingResponse(resp.aiter_raw(), status_code=resp.status_code, headers=out,
                             background=BackgroundTask(resp.aclose))


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
