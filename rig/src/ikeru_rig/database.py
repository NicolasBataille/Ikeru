"""SQLite persistence layer for the job queue.

We use raw `aiosqlite` rather than an ORM to keep the dependency surface tiny —
the schema is one table and we never need migrations beyond the initial create.
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Any

import aiosqlite

from .models import JobRecord, JobStatus, JobType

SCHEMA = """
CREATE TABLE IF NOT EXISTS jobs (
    id TEXT PRIMARY KEY NOT NULL,
    type TEXT NOT NULL,
    status TEXT NOT NULL,
    params_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    started_at TEXT,
    finished_at TEXT,
    asset_path TEXT,
    error TEXT
);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs(created_at);
"""


class Database:
    """Async SQLite wrapper for the jobs table."""

    def __init__(self, path: str) -> None:
        self._path = path

    async def connect(self) -> None:
        """Open the connection and ensure schema exists."""
        async with self._conn() as db:
            await db.executescript(SCHEMA)
            await db.commit()

    @asynccontextmanager
    async def _conn(self) -> AsyncIterator[aiosqlite.Connection]:
        async with aiosqlite.connect(self._path) as db:
            db.row_factory = aiosqlite.Row
            yield db

    # MARK: - Insert / update

    async def insert(self, record: JobRecord) -> None:
        async with self._conn() as db:
            await db.execute(
                """
                INSERT INTO jobs (id, type, status, params_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (
                    record.id,
                    record.type.value,
                    record.status.value,
                    json.dumps(record.params),
                    record.created_at.isoformat(),
                ),
            )
            await db.commit()

    async def update_status(
        self,
        job_id: str,
        status: JobStatus,
        *,
        started_at: datetime | None = None,
        finished_at: datetime | None = None,
        asset_path: str | None = None,
        error: str | None = None,
    ) -> None:
        fields: list[str] = ["status = ?"]
        values: list[Any] = [status.value]
        if started_at is not None:
            fields.append("started_at = ?")
            values.append(started_at.isoformat())
        if finished_at is not None:
            fields.append("finished_at = ?")
            values.append(finished_at.isoformat())
        if asset_path is not None:
            fields.append("asset_path = ?")
            values.append(asset_path)
        if error is not None:
            fields.append("error = ?")
            values.append(error)
        values.append(job_id)

        async with self._conn() as db:
            await db.execute(
                f"UPDATE jobs SET {', '.join(fields)} WHERE id = ?",  # noqa: S608
                values,
            )
            await db.commit()

    # MARK: - Read

    async def get(self, job_id: str) -> JobRecord | None:
        async with self._conn() as db:
            cursor = await db.execute("SELECT * FROM jobs WHERE id = ?", (job_id,))
            row = await cursor.fetchone()
            return _row_to_record(row) if row else None

    async def fetch_next_queued(self) -> JobRecord | None:
        """Fetch the oldest queued job for worker pickup."""
        async with self._conn() as db:
            cursor = await db.execute(
                "SELECT * FROM jobs WHERE status = ? ORDER BY created_at ASC LIMIT 1",
                (JobStatus.queued.value,),
            )
            row = await cursor.fetchone()
            return _row_to_record(row) if row else None

    async def delete(self, job_id: str) -> None:
        async with self._conn() as db:
            await db.execute("DELETE FROM jobs WHERE id = ?", (job_id,))
            await db.commit()


def _row_to_record(row: aiosqlite.Row) -> JobRecord:
    return JobRecord(
        id=row["id"],
        type=JobType(row["type"]),
        status=JobStatus(row["status"]),
        params=json.loads(row["params_json"]),
        created_at=datetime.fromisoformat(row["created_at"]),
        started_at=datetime.fromisoformat(row["started_at"]) if row["started_at"] else None,
        finished_at=datetime.fromisoformat(row["finished_at"]) if row["finished_at"] else None,
        asset_path=row["asset_path"],
        error=row["error"],
    )
