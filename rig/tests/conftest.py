"""Shared test fixtures for the ikeru-rig pytest suite."""

from __future__ import annotations

from collections.abc import AsyncIterator
from pathlib import Path

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from ikeru_rig import encoding as encoding_module
from ikeru_rig.config import Settings
from ikeru_rig.main import build_app
from ikeru_rig.voicevox import VoicevoxBackend


class MockVoicevox(VoicevoxBackend):
    """In-memory mock that returns canned WAV bytes regardless of input."""

    canned_wav = b"RIFF\x00\x00\x00\x00WAVEfmt "  # tiny placeholder

    def __init__(self, *, healthy: bool = True) -> None:
        self.healthy = healthy
        self.calls: list[dict[str, object]] = []

    async def synthesize(
        self,
        *,
        text: str,
        speaker_id: int,
        speed_scale: float,
        pitch_scale: float,
        intonation_scale: float,
    ) -> bytes:
        self.calls.append(
            {
                "text": text,
                "speaker_id": speaker_id,
                "speed_scale": speed_scale,
                "pitch_scale": pitch_scale,
                "intonation_scale": intonation_scale,
            }
        )
        return self.canned_wav

    async def health(self) -> bool:
        return self.healthy


@pytest.fixture
def mock_voicevox() -> MockVoicevox:
    return MockVoicevox()


@pytest.fixture
def test_settings(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Settings:
    """Per-test isolated settings: temp asset dir, temp sqlite, fixed token."""
    asset_dir = tmp_path / "assets"
    db_path = tmp_path / "rig.db"
    monkeypatch.setenv("IKERU_RIG_SHARED_TOKEN", "test-token")
    monkeypatch.setenv("IKERU_RIG_ASSET_DIR", str(asset_dir))
    monkeypatch.setenv("IKERU_RIG_DATABASE_URL", f"sqlite+aiosqlite:///{db_path}")
    # Reload the module-level settings instance
    from importlib import reload

    from ikeru_rig import config as config_module
    reload(config_module)
    return config_module.settings


@pytest_asyncio.fixture
async def client(
    test_settings: Settings,
    mock_voicevox: MockVoicevox,
    monkeypatch: pytest.MonkeyPatch,
) -> AsyncIterator[AsyncClient]:
    """Async HTTP client wired to a mocked-VOICEVOX FastAPI app.

    The encoding step is replaced with a no-op that just writes the wav bytes
    straight to the asset path so we don't depend on ffmpeg in CI.
    """

    async def fake_encode(
        *,
        wav_bytes: bytes,
        output_path: Path,
        bitrate: str = "32k",
        sample_rate: int = 16_000,
        ffmpeg_bin: str = "ffmpeg",
    ) -> Path:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(wav_bytes)
        return output_path

    monkeypatch.setattr(encoding_module, "encode_to_opus", fake_encode)
    # Also patch the imported reference inside the queue module
    from ikeru_rig import queue as queue_module
    monkeypatch.setattr(queue_module, "encode_to_opus", fake_encode)

    app = build_app(app_settings=test_settings, voicevox_backend=mock_voicevox)
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://test",
        headers={"X-Ikeru-Token": "test-token"},
    ) as ac:
        # Trigger lifespan startup
        async with app.router.lifespan_context(app):
            yield ac
