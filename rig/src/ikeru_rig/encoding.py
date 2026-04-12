"""Audio re-encoding helpers — wraps the system ffmpeg binary."""

from __future__ import annotations

import asyncio
import shutil
from pathlib import Path

import structlog

logger = structlog.get_logger(__name__)


class FfmpegError(RuntimeError):
    """Raised when ffmpeg exits with a non-zero status."""


async def encode_to_opus(
    *,
    wav_bytes: bytes,
    output_path: Path,
    bitrate: str = "32k",
    sample_rate: int = 16_000,
    ffmpeg_bin: str = "ffmpeg",
) -> Path:
    """Re-encode WAV bytes to mono Opus and persist to `output_path`.

    32 kbps mono 16 kHz Opus is intelligible enough for Japanese TTS while
    keeping a 3-4 second sentence under ~14 KB.
    """
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if shutil.which(ffmpeg_bin) is None:
        raise FfmpegError(f"ffmpeg binary not found in PATH: {ffmpeg_bin}")

    proc = await asyncio.create_subprocess_exec(
        ffmpeg_bin,
        "-y",                          # overwrite output
        "-loglevel", "error",
        "-f", "wav",
        "-i", "pipe:0",                # read WAV from stdin
        "-ac", "1",                    # mono
        "-ar", str(sample_rate),
        "-c:a", "libopus",
        "-b:a", bitrate,
        "-application", "voip",        # voice-optimised mode
        str(output_path),
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.PIPE,
    )

    _stdout, stderr = await proc.communicate(input=wav_bytes)
    if proc.returncode != 0:
        message = stderr.decode("utf-8", errors="replace").strip()
        logger.error("ffmpeg.encode_failed", returncode=proc.returncode, stderr=message)
        raise FfmpegError(f"ffmpeg returned {proc.returncode}: {message}")

    return output_path
