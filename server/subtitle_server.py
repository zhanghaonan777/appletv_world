#!/usr/bin/env python3
"""WorldTV subtitle server — runs on the Mac.

The Apple TV app taps the playing channel's audio and streams 16 kHz mono
float32 PCM here over a WebSocket. This server transcribes + translates it and
sends subtitle text back.

Pipeline:
  faster-whisper  (task=translate -> English, from any source language)
  argostranslate  (English -> Chinese, offline)

Run:
  pip install -r requirements.txt
  python3 subtitle_server.py
"""

import asyncio
import json

import numpy as np
import websockets
from faster_whisper import WhisperModel
import argostranslate.package
import argostranslate.translate

# --- Config -----------------------------------------------------------------

HOST = "0.0.0.0"
PORT = 8765
SAMPLE_RATE = 16000
WINDOW_SECONDS = 5.0          # transcribe this many seconds at a time
WHISPER_MODEL = "small"       # tiny / base / small / medium / large-v3

# --- Model loading ----------------------------------------------------------

print(f"Loading Whisper model '{WHISPER_MODEL}' ...")
whisper_model = WhisperModel(WHISPER_MODEL, device="auto", compute_type="auto")
print("Whisper ready.")


def ensure_translation_package():
    """Install the offline English->Chinese Argos package if missing."""
    installed = argostranslate.translate.get_installed_languages()
    have_en = any(lang.code == "en" for lang in installed)
    have_zh = any(lang.code == "zh" for lang in installed)
    if have_en and have_zh:
        print("Translation package (en->zh) already installed.")
        return
    print("Installing en->zh translation package ...")
    argostranslate.package.update_package_index()
    available = argostranslate.package.get_available_packages()
    pkg = next((p for p in available if p.from_code == "en" and p.to_code == "zh"), None)
    if pkg is None:
        print("WARNING: en->zh package not found — translation will be skipped.")
        return
    argostranslate.package.install_from_path(pkg.download())
    print("Translation package installed.")


ensure_translation_package()


def translate_to_chinese(text: str) -> str:
    try:
        return argostranslate.translate.translate(text, "en", "zh")
    except Exception as exc:  # noqa: BLE001 - never let translation crash a session
        print("translate error:", exc)
        return text


# --- WebSocket session ------------------------------------------------------

async def handle_client(websocket):
    peer = getattr(websocket, "remote_address", "?")
    print(f"client connected: {peer}")
    buffer = np.zeros(0, dtype=np.float32)
    window = int(WINDOW_SECONDS * SAMPLE_RATE)
    total_samples = 0

    try:
        async for message in websocket:
            if not isinstance(message, (bytes, bytearray)):
                continue
            chunk = np.frombuffer(message, dtype=np.float32)
            buffer = np.concatenate([buffer, chunk])
            total_samples += len(chunk)

            while len(buffer) >= window:
                audio = buffer[:window]
                buffer = buffer[window:]

                segments, info = whisper_model.transcribe(
                    audio, task="translate", vad_filter=True
                )
                english = " ".join(seg.text.strip() for seg in segments).strip()
                rms = float(np.sqrt(np.mean(audio ** 2)))
                print(f"window | total={total_samples / SAMPLE_RATE:.0f}s "
                      f"rms={rms:.4f} lang={info.language} text='{english}'")
                if not english:
                    continue

                chinese = translate_to_chinese(english)
                await websocket.send(json.dumps({
                    "original": english,
                    "translated": chinese,
                }))
                print(f"[{info.language}] {english}  ->  {chinese}")
    except websockets.ConnectionClosed:
        pass
    print(f"client disconnected: {peer}")


async def main():
    print(f"WorldTV subtitle server listening on ws://{HOST}:{PORT}")
    async with websockets.serve(handle_client, HOST, PORT, max_size=None):
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
