# ikeru-rig — Local GPU Bridge for Ikeru

> Personal-use Docker stack that runs **VOICEVOX** (Japanese TTS with native pitch
> accent) on your PC and exposes a job queue REST API to the iPhone client.

## What this gives you

Your iPhone asks for the audio of `食べる` → your PC's RTX GPU synthesises the
WAV via VOICEVOX in <1 second → ffmpeg re-encodes it to **Opus 32 kbps mono** (~14 KB)
→ the iPhone caches it locally with content addressing and quota.

Result: **irreproachable Japanese pronunciation** with **near-zero data transfer**
and **zero cloud cost**.

## Architecture

```
┌─────────────────────────────┐                   ┌──────────────┐
│  PC (Windows + WSL2 + GPU)  │                   │   iPhone     │
│                             │                   │              │
│  ┌──────────┐  ┌─────────┐  │  shared-secret    │  Ikeru.app   │
│  │ikeru-rig │→ │voicevox │  │←── HTTP/JSON ────→│  ├─ RigClient│
│  │ FastAPI  │  │ engine  │  │                   │  ├─ AssetCache│
│  │ + queue  │  │ (CUDA)  │  │                   │  └─ AudioCoord│
│  └──────────┘  └─────────┘  │                   │              │
└─────────────────────────────┘                   └──────────────┘
       :8787              :50021
```

## Prerequisites (Windows + Docker Desktop)

1. **Windows 11** (or Windows 10 21H2+)
2. **NVIDIA GPU** with recent drivers (GeForce 535+ recommended)
3. **WSL2** enabled — `wsl --install` from PowerShell as admin
4. **Docker Desktop for Windows** — install from <https://docs.docker.com/desktop/install/windows-install/>
5. In Docker Desktop → Settings → General → enable **"Use the WSL 2 based engine"**
6. In Docker Desktop → Settings → Resources → WSL Integration → enable for your distro
7. **NVIDIA Container Toolkit** for WSL2 — follow the official guide:
   <https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#installing-with-apt>
8. Verify GPU passthrough:
   ```bash
   docker run --rm --gpus all nvidia/cuda:12.5.0-base-ubuntu22.04 nvidia-smi
   ```
   You should see your GPU listed.

## Setup

```bash
# 1. Clone or open this directory
cd rig/

# 2. Generate a long random shared secret (used by the iPhone too)
openssl rand -hex 32 > shared_token.txt    # save it somewhere

# 3. Create your local .env from the template
cp .env.example .env
# Edit .env and paste the token from step 2 into IKERU_RIG_SHARED_TOKEN

# 4. Pull and start
docker compose up -d
```

First start downloads the VOICEVOX engine image (~3 GB) — this takes a few minutes.
Subsequent starts take seconds.

## Verify

```bash
# Health (no auth needed)
curl http://localhost:8787/health
# {"status":"ok","voicevox":"ok","gpu":"available","version":"0.1.0"}

# Capabilities (auth required)
curl -H "X-Ikeru-Token: $(cat shared_token.txt)" http://localhost:8787/capabilities

# Queue a TTS job
curl -X POST http://localhost:8787/jobs \
  -H "X-Ikeru-Token: $(cat shared_token.txt)" \
  -H "Content-Type: application/json" \
  -d '{"type":"tts","params":{"text":"こんにちは","speaker_id":3}}'
# {"job_id":"abc...","status":"queued"}

# Wait for it to finish, then download the asset
curl -H "X-Ikeru-Token: $(cat shared_token.txt)" \
  http://localhost:8787/jobs/<job_id>/asset \
  --output hello.opus
```

Open `hello.opus` in any audio player — it should pronounce こんにちは clearly with
correct Japanese pitch accent.

## Connect from your iPhone (Ikeru app)

1. Find your PC's LAN IP: `ipconfig` → look for the WSL/Ethernet interface
2. In Ikeru → Settings → AI Providers → Local Rig:
   - **Rig URL:** `http://<your-pc-ip>:8787`
   - **Shared token:** paste the one from `shared_token.txt`
3. Tap **Test connection** — should show a green dot

## REST API

All endpoints except `/health` require the `X-Ikeru-Token` header.

| Method | Path | Description |
|---|---|---|
| GET | `/health` | Liveness probe (no auth) |
| GET | `/capabilities` | Supported job types and speakers |
| POST | `/jobs` | Enqueue a job. Returns `{job_id, status}` |
| GET | `/jobs/{id}` | Job status + metadata |
| GET | `/jobs/{id}/asset` | Stream the binary result |
| DELETE | `/jobs/{id}` | Cancel/evict a job and its asset |

### TTS job parameters

```json
{
  "type": "tts",
  "params": {
    "text": "こんにちは",
    "speaker_id": 3,
    "speed_scale": 1.0,
    "pitch_scale": 0.0,
    "intonation_scale": 1.0
  }
}
```

`speaker_id` defaults to **3 (Zundamon Normal)**. Browse other VOICEVOX
speakers at <http://localhost:50021/speakers> after `docker compose up`.

## Development (without Docker)

```bash
python3.12 -m venv .venv
source .venv/bin/activate          # or .venv\Scripts\activate on Windows
pip install -e ".[dev]"

# Run the test suite (uses an in-memory mock VOICEVOX)
pytest

# Run the dev server (you still need a real VOICEVOX endpoint for real synthesis)
export IKERU_RIG_VOICEVOX_URL=http://localhost:50021
export IKERU_RIG_SHARED_TOKEN=dev
ikeru-rig
```

## Logs and troubleshooting

```bash
# Live logs
docker compose logs -f ikeru-rig
docker compose logs -f voicevox

# Restart everything
docker compose down && docker compose up -d

# Wipe the job DB and asset cache (does NOT touch the iPhone cache)
docker compose down -v
```

| Symptom | Likely cause | Fix |
|---|---|---|
| `voicevox: down` in `/health` | VOICEVOX container still booting | Wait 30s, retry |
| `gpu: missing` | NVIDIA Container Toolkit not installed in WSL2 | Re-do prereq step 7 |
| iPhone can't reach `http://...:8787` | Windows Defender firewall blocks port 8787 | Add inbound rule for TCP 8787 from your LAN |
| 401 Unauthorized | Token mismatch | Re-paste exactly what's in `shared_token.txt` |

## Security notes

- **LAN-only deployment.** Do not expose port 8787 to the public internet.
  The shared-secret header is fine for personal LAN use but is NOT a real
  authentication system.
- **Never commit `.env` or `shared_token.txt`.** Both are gitignored.
- **Personal use only.** This stack is not designed for multi-user or
  production deployment.

## Roadmap

- **Story 7-5:** SRS-aware pre-warming triggered from the iPhone client
- **Future:** Style-Bert-VITS2 for voice cloning (your own voice for shadowing)
- **Future:** Stable Diffusion for kanji mnemonic illustrations
- **Future:** Whisper for offline pronunciation feedback
- **Future:** Tailscale advertising so the rig is reachable from anywhere
