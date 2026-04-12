"""Runtime configuration loaded from environment variables (or `.env`)."""

from __future__ import annotations

from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Process-wide configuration.

    All fields can be overridden via environment variables prefixed with
    `IKERU_RIG_`. A `.env` file at the project root is also honoured.
    """

    model_config = SettingsConfigDict(
        env_prefix="IKERU_RIG_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # HTTP server
    host: str = "0.0.0.0"
    port: int = 8787

    # Shared-secret authentication header
    shared_token: str = Field(default="dev", description="Token clients must send in X-Ikeru-Token")

    # SQLite database path (relative to project root by default)
    database_url: str = "sqlite+aiosqlite:///rig.db"

    # Storage location for generated assets
    asset_dir: Path = Path("assets")

    # VOICEVOX engine endpoint (the side-by-side container)
    voicevox_url: str = "http://voicevox:50021"
    voicevox_default_speaker: int = 3  # Zundamon Normal

    # ffmpeg binary (relative or absolute)
    ffmpeg_bin: str = "ffmpeg"

    # Worker pool
    worker_concurrency: int = 1

    def ensure_dirs(self) -> None:
        """Create asset directory if missing."""
        self.asset_dir.mkdir(parents=True, exist_ok=True)


settings = Settings()
