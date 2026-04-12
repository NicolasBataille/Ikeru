FROM python:3.12-slim

# System deps: ffmpeg for opus encoding, curl for healthchecks
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python deps first for layer caching
COPY pyproject.toml ./
COPY src ./src

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir .

# Asset directory must be writable
RUN mkdir -p /app/assets

EXPOSE 8787

ENV IKERU_RIG_HOST=0.0.0.0 \
    IKERU_RIG_PORT=8787 \
    IKERU_RIG_ASSET_DIR=/app/assets \
    IKERU_RIG_DATABASE_URL=sqlite+aiosqlite:////app/rig.db \
    IKERU_RIG_VOICEVOX_URL=http://voicevox:50021

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8787/health || exit 1

CMD ["uvicorn", "ikeru_rig.main:app", "--host", "0.0.0.0", "--port", "8787"]
