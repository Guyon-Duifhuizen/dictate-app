"""Headless speech-to-text worker — JSON lines over stdin/stdout.

Protocol
--------
Swift -> Python (stdin):
    {"type":"start","language":"en-US"}
    {"type":"stop"}

Python -> Swift (stdout):
    {"type":"ready"}
    {"type":"interim","text":"hello wor","audio_level":0.73}
    {"type":"final","text":"hello world."}
    {"type":"error","message":"..."}
    {"type":"stopped"}
"""

from __future__ import annotations

import json
import math
import struct
import sys
import threading
import queue

import pyaudio
from google.cloud import speech

from dictate_app.config import Config


def _emit(event: dict) -> None:
    json.dump(event, sys.stdout)
    sys.stdout.write("\n")
    sys.stdout.flush()


def _log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def _rms(data: bytes) -> float:
    n = len(data) // 2
    if n == 0:
        return 0.0
    samples = struct.unpack(f"<{n}h", data)
    return math.sqrt(sum(s * s for s in samples) / n)


def _normalize_rms(rms: float) -> float:
    if rms < 1:
        return 0.0
    return min(1.0, math.log10(rms) / math.log10(5000))


def _make_audio_callback(audio_queue: queue.Queue, stop_event: threading.Event, rms_holder: list):
    """Return a PyAudio stream callback that pushes chunks to the queue."""
    def callback(in_data, frame_count, time_info, status_flags):
        if stop_event.is_set():
            return (None, pyaudio.paComplete)
        if in_data is not None:
            rms_holder[0] = _rms(in_data)
            audio_queue.put(in_data)
        return (None, pyaudio.paContinue)
    return callback


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


def _run_session(config: Config, pa: pyaudio.PyAudio, client: speech.SpeechClient,
                 stop_event: threading.Event) -> None:
    """Open mic, stream to Google Speech, emit JSON events. Blocks until stopped."""
    audio_queue: queue.Queue[bytes | None] = queue.Queue()
    rms_holder = [0.0]  # mutable container for current RMS

    _log(f"[session] Opening mic: rate={config.sample_rate} channels={config.audio_channels}")
    stream = pa.open(
        format=pyaudio.paInt16,
        channels=config.audio_channels,
        rate=config.sample_rate,
        input=True,
        frames_per_buffer=config.chunk_frames,
        stream_callback=_make_audio_callback(audio_queue, stop_event, rms_holder),
    )

    _log(f"[session] Connecting to Google Speech v1 API (model={config.model})")
    recognition_config = speech.RecognitionConfig(
        encoding=speech.RecognitionConfig.AudioEncoding.LINEAR16,
        sample_rate_hertz=config.sample_rate,
        language_code=config.language,
        model=config.model,
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
                    _emit({
                        "type": "interim",
                        "text": combined,
                        "audio_level": round(_normalize_rms(rms_holder[0]), 3),
                    })
    except Exception as e:
        _emit({"type": "error", "message": str(e)})
    finally:
        try:
            stream.stop_stream()
            stream.close()
        except Exception:
            pass


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
    config = Config()
    pa = pyaudio.PyAudio()
    client = speech.SpeechClient()

    _emit({"type": "ready"})

    stop_event: threading.Event | None = None
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
            _stop_session(stop_event, None, session_thread)

            language = cmd.get("language", config.language)
            config.language = language

            stop_event = threading.Event()
            session_thread = threading.Thread(
                target=_run_session,
                args=(config, pa, client, stop_event),
                daemon=True,
            )
            session_thread.start()

        elif cmd_type == "stop":
            _stop_session(stop_event, None, session_thread)
            stop_event = None
            session_thread = None
            _emit({"type": "stopped"})

    pa.terminate()


if __name__ == "__main__":
    main()
