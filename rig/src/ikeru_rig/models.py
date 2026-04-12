"""Pydantic and SQL models for jobs."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class JobType(str, Enum):
    """Supported job types. Add new entries here as the rig grows."""

    tts = "tts"


class JobStatus(str, Enum):
    """Lifecycle states for a job."""

    queued = "queued"
    running = "running"
    done = "done"
    error = "error"


class TTSParams(BaseModel):
    """Parameters for a `tts` job."""

    text: str = Field(..., min_length=1, max_length=2000)
    speaker_id: int = Field(default=3)
    speed_scale: float = Field(default=1.0, ge=0.5, le=2.0)
    pitch_scale: float = Field(default=0.0, ge=-0.15, le=0.15)
    intonation_scale: float = Field(default=1.0, ge=0.0, le=2.0)


class JobRequest(BaseModel):
    """Incoming job enqueue request."""

    type: JobType
    params: dict[str, Any]


class JobRecord(BaseModel):
    """Public job representation returned by the API."""

    id: str
    type: JobType
    status: JobStatus
    params: dict[str, Any]
    created_at: datetime
    started_at: datetime | None = None
    finished_at: datetime | None = None
    asset_path: str | None = None
    error: str | None = None


class HealthResponse(BaseModel):
    """Response payload for `GET /health`."""

    status: str
    voicevox: str
    gpu: str
    version: str


class CapabilitiesResponse(BaseModel):
    """Response payload for `GET /capabilities`."""

    job_types: list[str]
    voicevox_speakers: list[int] | None = None


class EnqueueResponse(BaseModel):
    """Response payload for `POST /jobs`."""

    job_id: str
    status: JobStatus
