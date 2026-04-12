"""FastAPI application — entrypoint for the ikeru-rig REST orchestrator."""

from __future__ import annotations

from contextlib import asynccontextmanager
from pathlib import Path
from typing import AsyncIterator

import structlog
from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse

from . import __version__
from .config import Settings, settings
from .database import Database
from .models import (
    CapabilitiesResponse,
    EnqueueResponse,
    HealthResponse,
    JobRecord,
    JobRequest,
    JobStatus,
    JobType,
    TTSParams,
)
from .queue import JobQueue
from .voicevox import VoicevoxBackend, VoicevoxClient

logger = structlog.get_logger(__name__)


# MARK: - App state

class AppState:
    """Container for shared singletons attached to `app.state`."""

    def __init__(self, db: Database, queue: JobQueue, voicevox: VoicevoxBackend) -> None:
        self.db = db
        self.queue = queue
        self.voicevox = voicevox


# MARK: - Auth dependency

def make_token_dependency(cfg: Settings):
    """Build a FastAPI dependency that enforces the shared-secret header.

    The dependency is built per-app so tests can use a different token without
    fighting the module-level `settings` import.
    """

    def require_token(request: Request) -> None:
        expected = cfg.shared_token
        received = request.headers.get("X-Ikeru-Token", "")
        if not expected or received != expected:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing or invalid X-Ikeru-Token header",
            )

    return require_token


# MARK: - Lifespan

def build_app(
    *,
    app_settings: Settings | None = None,
    voicevox_backend: VoicevoxBackend | None = None,
) -> FastAPI:
    """Construct a FastAPI app. Tests pass a mock backend; production uses the default."""
    cfg = app_settings or settings
    cfg.ensure_dirs()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        db = Database(_sqlite_path(cfg.database_url))
        await db.connect()
        backend: VoicevoxBackend = voicevox_backend or VoicevoxClient(cfg.voicevox_url)
        queue = JobQueue(db=db, voicevox=backend, settings=cfg)
        await queue.start()
        app.state.ikeru = AppState(db=db, queue=queue, voicevox=backend)
        try:
            yield
        finally:
            await queue.stop()

    app = FastAPI(
        title="ikeru-rig",
        version=__version__,
        description="Local GPU bridge for Ikeru — TTS / images / transcription job queue.",
        lifespan=lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    _register_routes(app, cfg)
    return app


def _register_routes(app: FastAPI, cfg: Settings) -> None:
    require_token = make_token_dependency(cfg)

    @app.get("/health", response_model=HealthResponse)
    async def health() -> HealthResponse:
        backend: VoicevoxBackend = app.state.ikeru.voicevox
        voicevox_ok = await backend.health()
        return HealthResponse(
            status="ok",
            voicevox="ok" if voicevox_ok else "down",
            gpu="available",  # TODO: read nvidia-smi when available
            version=__version__,
        )

    @app.get("/capabilities", response_model=CapabilitiesResponse, dependencies=[Depends(require_token)])
    async def capabilities() -> CapabilitiesResponse:
        return CapabilitiesResponse(
            job_types=[t.value for t in JobType],
            voicevox_speakers=[cfg.voicevox_default_speaker],
        )

    @app.post(
        "/jobs",
        response_model=EnqueueResponse,
        status_code=status.HTTP_202_ACCEPTED,
        dependencies=[Depends(require_token)],
    )
    async def enqueue(request: JobRequest) -> EnqueueResponse:
        # Validate type-specific params eagerly so the client gets a 422 immediately
        if request.type is JobType.tts:
            try:
                TTSParams(**request.params)
            except Exception as exc:
                raise HTTPException(status_code=422, detail=str(exc)) from exc

        record = await app.state.ikeru.queue.enqueue(request)
        return EnqueueResponse(job_id=record.id, status=record.status)

    @app.get("/jobs/{job_id}", response_model=JobRecord, dependencies=[Depends(require_token)])
    async def get_job(job_id: str) -> JobRecord:
        record = await app.state.ikeru.queue.get(job_id)
        if record is None:
            raise HTTPException(status_code=404, detail="Job not found")
        return record

    @app.get("/jobs/{job_id}/asset", dependencies=[Depends(require_token)])
    async def get_asset(job_id: str) -> FileResponse:
        record = await app.state.ikeru.queue.get(job_id)
        if record is None:
            raise HTTPException(status_code=404, detail="Job not found")
        if record.status is not JobStatus.done or record.asset_path is None:
            raise HTTPException(status_code=409, detail=f"Job is in state {record.status.value}")
        path = Path(record.asset_path)
        if not path.exists():
            raise HTTPException(status_code=410, detail="Asset has been evicted")
        return FileResponse(
            path,
            media_type="audio/opus",
            filename=path.name,
        )

    @app.delete("/jobs/{job_id}", dependencies=[Depends(require_token)])
    async def delete_job(job_id: str) -> JSONResponse:
        record = await app.state.ikeru.queue.get(job_id)
        if record is None:
            raise HTTPException(status_code=404, detail="Job not found")
        # If the asset file exists, remove it too
        if record.asset_path:
            try:
                Path(record.asset_path).unlink(missing_ok=True)
            except OSError:
                logger.warning("delete.unlink_failed", asset_path=record.asset_path)
        await app.state.ikeru.queue.delete(job_id)
        return JSONResponse({"deleted": job_id})


def _sqlite_path(database_url: str) -> str:
    """Convert a sqlalchemy-style URL to a raw aiosqlite path."""
    prefix = "sqlite+aiosqlite:///"
    if database_url.startswith(prefix):
        return database_url[len(prefix):]
    return database_url


# Module-level app instance for `uvicorn ikeru_rig.main:app`
app = build_app()


def run() -> None:
    """Entrypoint for `ikeru-rig` console script."""
    import uvicorn

    uvicorn.run(
        "ikeru_rig.main:app",
        host=settings.host,
        port=settings.port,
        reload=False,
    )
