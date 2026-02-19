"""Headless speech-to-text worker — JSON lines over stdin/stdout.

Protocol
--------
Swift -> Python (stdin):
    {"type":"start","language":"en-US"}
    {"type":"audio","data":"<base64 PCM bytes>"}
    {"type":"stop"}

Python -> Swift (stdout):
    {"type":"ready"}
    {"type":"interim","text":"hello wor"}
    {"type":"final","text":"hello world."}
    {"type":"error","message":"..."}
    {"type":"stopped"}
"""

from __future__ import annotations

import base64
import json
import sys
import threading
import tomllib
import queue
from pathlib import Path

from google.cloud import speech

_CONFIG = tomllib.loads((Path(__file__).parent / "config.toml").read_text())


def _emit(event: dict) -> None:
    json.dump(event, sys.stdout)
    sys.stdout.write("\n")
    sys.stdout.flush()


def _log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def _audio_generator(audio_queue: queue.Queue, stop_event: threading.Event):
    """Yield audio chunks until stop is signalled."""
    while not stop_event.is_set():
        try:
            chunk = audio_queue.get(timeout=0.5)
        except queue.Empty:
            continue
        if chunk is None:
            return
        yield chunk


def _run_session(language: str, client: speech.SpeechClient,
                 audio_queue: queue.Queue,
                 stop_event: threading.Event) -> None:
    """Stream audio from queue to Google Speech, emit JSON events. Blocks until stopped."""
    model = _CONFIG["model"]
    sample_rate = _CONFIG["sample_rate"]
    _log(f"[session] Connecting to Google Speech v1 API (model={model})")
    recognition_config = speech.RecognitionConfig(
        encoding=speech.RecognitionConfig.AudioEncoding.LINEAR16,
        sample_rate_hertz=sample_rate,
        language_code=language,
        model=model,
        enable_automatic_punctuation=True,
    )
    streaming_config = speech.StreamingRecognitionConfig(
        config=recognition_config,
        interim_results=True,
    )

    def request_generator():
        for chunk in _audio_generator(audio_queue, stop_event):
            yield speech.StreamingRecognizeRequest(audio_content=chunk)

    try:
        responses = client.streaming_recognize(
            config=streaming_config,
            requests=request_generator(),
        )
        for response in responses:
            interim_parts = []
            for result in response.results:
                if not result.alternatives:
                    continue
                transcript = result.alternatives[0].transcript
                if result.is_final:
                    text = transcript.strip()
                    if text:
                        _emit({"type": "final", "text": text})
                else:
                    interim_parts.append(transcript)

            if interim_parts:
                combined = "".join(interim_parts)
                if combined:
                    _emit({"type": "interim", "text": combined})
    except Exception as e:
        _emit({"type": "error", "message": str(e)})


def _stop_session(stop_event: threading.Event | None, audio_queue: queue.Queue | None,
                  thread: threading.Thread | None) -> None:
    """Signal a running session to stop and wait for it."""
    if stop_event is not None:
        stop_event.set()
    if audio_queue is not None:
        audio_queue.put(None)
    if thread is not None:
        thread.join(timeout=5.0)


def main() -> None:
    client = speech.SpeechClient()

    _emit({"type": "ready"})

    stop_event: threading.Event | None = None
    audio_queue: queue.Queue | None = None
    session_thread: threading.Thread | None = None

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        _log(f"[worker] Received command: {line}")

        try:
            cmd = json.loads(line)
        except json.JSONDecodeError:
            _log(f"[worker] invalid JSON: {line}")
            continue

        cmd_type = cmd.get("type")

        if cmd_type == "start":
            _stop_session(stop_event, audio_queue, session_thread)

            language = cmd.get("language", _CONFIG["language"])

            stop_event = threading.Event()
            audio_queue = queue.Queue()
            session_thread = threading.Thread(
                target=_run_session,
                args=(language, client, audio_queue, stop_event),
                daemon=True,
            )
            session_thread.start()

        elif cmd_type == "audio":
            if audio_queue is not None and stop_event is not None and not stop_event.is_set():
                try:
                    pcm_bytes = base64.b64decode(cmd["data"])
                    audio_queue.put(pcm_bytes)
                except (KeyError, Exception) as e:
                    _log(f"[worker] bad audio message: {e}")

        elif cmd_type == "stop":
            _stop_session(stop_event, audio_queue, session_thread)
            stop_event = None
            audio_queue = None
            session_thread = None
            _emit({"type": "stopped"})


if __name__ == "__main__":
    main()
