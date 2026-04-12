"""Thin async wrapper around the VOICEVOX engine REST API."""

from __future__ import annotations

from typing import Any, Protocol

import httpx


class VoicevoxBackend(Protocol):
    """Protocol that production and mock backends both implement."""

    async def synthesize(
        self,
        *,
        text: str,
        speaker_id: int,
        speed_scale: float,
        pitch_scale: float,
        intonation_scale: float,
    ) -> bytes:
        """Return the WAV bytes for a synthesised utterance."""
        ...

    async def health(self) -> bool:
        """Return True if the engine is reachable."""
        ...


class VoicevoxClient(VoicevoxBackend):
    """Production VOICEVOX client speaking the documented REST API."""

    def __init__(self, base_url: str, *, timeout: float = 30.0) -> None:
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout

    async def synthesize(
        self,
        *,
        text: str,
        speaker_id: int,
        speed_scale: float,
        pitch_scale: float,
        intonation_scale: float,
    ) -> bytes:
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            # Step 1: build an audio query for the text
            query_resp = await client.post(
                f"{self._base_url}/audio_query",
                params={"text": text, "speaker": speaker_id},
            )
            query_resp.raise_for_status()
            query: dict[str, Any] = query_resp.json()

            # Apply our parameter overrides
            query["speedScale"] = speed_scale
            query["pitchScale"] = pitch_scale
            query["intonationScale"] = intonation_scale

            # Step 2: synthesize WAV from the (possibly modified) query
            synth_resp = await client.post(
                f"{self._base_url}/synthesis",
                params={"speaker": speaker_id},
                json=query,
                headers={"Accept": "audio/wav"},
            )
            synth_resp.raise_for_status()
            return synth_resp.content

    async def health(self) -> bool:
        try:
            async with httpx.AsyncClient(timeout=2.0) as client:
                resp = await client.get(f"{self._base_url}/version")
                return resp.status_code == 200
        except httpx.HTTPError:
            return False
