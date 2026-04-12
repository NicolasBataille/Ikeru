"""End-to-end tests for the rig job queue REST API."""

from __future__ import annotations

import asyncio

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_health_returns_ok(client: AsyncClient) -> None:
    response = await client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["voicevox"] == "ok"


@pytest.mark.asyncio
async def test_capabilities_lists_tts(client: AsyncClient) -> None:
    response = await client.get("/capabilities")
    assert response.status_code == 200
    assert "tts" in response.json()["job_types"]


@pytest.mark.asyncio
async def test_missing_token_rejects_capabilities(client: AsyncClient) -> None:
    # Drop the token from this single request
    response = await client.get("/capabilities", headers={"X-Ikeru-Token": ""})
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_enqueue_invalid_params_returns_422(client: AsyncClient) -> None:
    response = await client.post(
        "/jobs",
        json={"type": "tts", "params": {"text": ""}},  # text fails min_length
    )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_full_tts_round_trip(client: AsyncClient) -> None:
    enqueue = await client.post(
        "/jobs",
        json={
            "type": "tts",
            "params": {"text": "こんにちは", "speaker_id": 3},
        },
    )
    assert enqueue.status_code == 202
    job_id = enqueue.json()["job_id"]
    assert job_id

    # Wait for the worker to process the job
    for _ in range(20):
        status_resp = await client.get(f"/jobs/{job_id}")
        assert status_resp.status_code == 200
        body = status_resp.json()
        if body["status"] == "done":
            break
        if body["status"] == "error":
            pytest.fail(f"Job failed: {body['error']}")
        await asyncio.sleep(0.1)
    else:
        pytest.fail("Job did not complete within 2 seconds")

    # Fetch the asset
    asset_resp = await client.get(f"/jobs/{job_id}/asset")
    assert asset_resp.status_code == 200
    assert asset_resp.headers["content-type"] == "audio/opus"
    assert len(asset_resp.content) > 0


@pytest.mark.asyncio
async def test_get_unknown_job_returns_404(client: AsyncClient) -> None:
    response = await client.get("/jobs/does-not-exist")
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_delete_job_removes_record(client: AsyncClient) -> None:
    enqueue = await client.post(
        "/jobs",
        json={"type": "tts", "params": {"text": "test"}},
    )
    job_id = enqueue.json()["job_id"]

    # Wait briefly for processing
    for _ in range(20):
        status_resp = await client.get(f"/jobs/{job_id}")
        if status_resp.json()["status"] in ("done", "error"):
            break
        await asyncio.sleep(0.1)

    delete = await client.delete(f"/jobs/{job_id}")
    assert delete.status_code == 200
    assert delete.json() == {"deleted": job_id}

    after = await client.get(f"/jobs/{job_id}")
    assert after.status_code == 404
