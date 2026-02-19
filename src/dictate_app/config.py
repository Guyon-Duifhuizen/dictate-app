from dataclasses import dataclass, field
import os
from pathlib import Path
import subprocess

_CACHE_FILE = Path.home() / ".dictate-app-project"


def _resolve_gcp_project() -> str:
    project = os.environ.get("GOOGLE_CLOUD_PROJECT", "")
    if project:
        return project

    try:
        project = _CACHE_FILE.read_text().strip()
        if project:
            return project
    except OSError:
        pass

    try:
        result = subprocess.run(
            ["gcloud", "config", "get-value", "project"],
            capture_output=True, text=True, timeout=5,
        )
        project = result.stdout.strip()
        if project:
            _CACHE_FILE.write_text(project)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return project


@dataclass
class Config:
    language: str = "en-US"
    sample_rate: int = 16000
    audio_channels: int = 1
    chunk_duration_ms: int = 100
    model: str = "latest_long"
    gcp_project: str = field(default_factory=_resolve_gcp_project)

    @property
    def chunk_frames(self) -> int:
        return int(self.sample_rate * self.chunk_duration_ms / 1000)

    def __post_init__(self) -> None:
        if not self.gcp_project:
            raise EnvironmentError(
                "Could not determine GCP project. Set GOOGLE_CLOUD_PROJECT "
                "or run: gcloud config set project <your-project>"
            )
