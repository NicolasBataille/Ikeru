"""Async background worker pool for the rig job queue."""

from __future__ import annotations

import asyncio
import hashlib
import json
import uuid
from datetime import datetime, timezone
from pathlib import Path

import structlog

from .config import Settings
from .database import Database
from .encoding import FfmpegError, encode_to_opus
from .models import JobRecord, JobRequest, JobStatus, JobType, TTSParams
from .voicevox import VoicevoxBackend

logger = structlog.get_logger(__name__)


class JobQueue:
    """In-process job queue backed by SQLite, drained by N async workers."""

    def __init__(
        self,
        *,
        db: Database,
        voicevox: VoicevoxBackend,
        settings: Settings,
    ) -> None:
        self._db = db
        self._voicevox = voicevox
        self._settings = settings
        self._wakeup = asyncio.Event()
        self._workers: list[asyncio.Task[None]] = []
        self._stopping = False

    # MARK: - Lifecycle

    async def start(self) -> None:
        """Spawn worker tasks."""
        for index in range(self._settings.worker_concurrency):
            self._workers.append(asyncio.create_task(self._worker_loop(index)))
        logger.info("queue.started", workers=len(self._workers))

    async def stop(self) -> None:
        """Cancel worker tasks and wait for them to exit."""
        self._stopping = True
        self._wakeup.set()
        for task in self._workers:
            task.cancel()
        for task in self._workers:
            try:
                await task
            except asyncio.CancelledError:
                pass
        self._workers.clear()
        logger.info("queue.stopped")

    # MARK: - Public API

    async def enqueue(self, request: JobRequest) -> JobRecord:
        """Persist a new queued job and wake the workers."""
        record = JobRecord(
            id=uuid.uuid4().hex,
            type=request.type,
            status=JobStatus.queued,
            params=request.params,
            created_at=datetime.now(timezone.utc),
        )
        await self._db.insert(record)
        self._wakeup.set()
        logger.info("queue.enqueued", job_id=record.id, type=record.type.value)
        return record

    async def get(self, job_id: str) -> JobRecord | None:
        return await self._db.get(job_id)

    async def delete(self, job_id: str) -> None:
        await self._db.delete(job_id)
        logger.info("queue.deleted", job_id=job_id)

    # MARK: - Worker loop

    async def _worker_loop(self, index: int) -> None:
        log = logger.bind(worker=index)
        log.info("worker.started")
        while not self._stopping:
            record = await self._db.fetch_next_queued()
            if record is None:
                self._wakeup.clear()
                try:
                    await asyncio.wait_for(self._wakeup.wait(), timeout=5.0)
                except asyncio.TimeoutError:
                    pass
                continue

            await self._process(record, log=log)

    async def _process(self, record: JobRecord, *, log: structlog.BoundLogger) -> None:
        log = log.bind(job_id=record.id, type=record.type.value)
        log.info("job.started")
        await self._db.update_status(
            record.id,
            JobStatus.running,
            started_at=datetime.now(timezone.utc),
        )

        try:
            asset_path = await self._dispatch(record)
            await self._db.update_status(
                record.id,
                JobStatus.done,
                finished_at=datetime.now(timezone.utc),
                asset_path=str(asset_path),
            )
            log.info("job.done", asset_path=str(asset_path))
        except Exception as exc:
            await self._db.update_status(
                record.id,
                JobStatus.error,
                finished_at=datetime.now(timezone.utc),
                error=f"{type(exc).__name__}: {exc}",
            )
            log.exception("job.failed")

    # MARK: - Dispatch by type

    async def _dispatch(self, record: JobRecord) -> Path:
        if record.type is JobType.tts:
            return await self._run_tts(record)
        raise ValueError(f"Unsupported job type: {record.type}")

    async def _run_tts(self, record: JobRecord) -> Path:
        params = TTSParams(**record.params)
        wav = await self._voicevox.synthesize(
            text=params.text,
            speaker_id=params.speaker_id,
            speed_scale=params.speed_scale,
            pitch_scale=params.pitch_scale,
            intonation_scale=params.intonation_scale,
        )

        cache_key = _content_hash(record.type.value, params.model_dump())
        output_path = self._settings.asset_dir / f"{cache_key}.opus"

        try:
            await encode_to_opus(
                wav_bytes=wav,
                output_path=output_path,
                ffmpeg_bin=self._settings.ffmpeg_bin,
            )
        except FfmpegError:
            raise

        return output_path


def _content_hash(job_type: str, params: dict[str, object]) -> str:
    """Stable content hash for asset deduplication."""
    blob = json.dumps({"type": job_type, "params": params}, sort_keys=True).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()[:32]
