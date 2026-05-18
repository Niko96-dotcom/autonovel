"""FastAPI backend for local Autonovel runs."""

from __future__ import annotations

import asyncio
import json
import os
import shutil
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, HTMLResponse, Response, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RUNS_DIR = PROJECT_ROOT / "runs"
WEB_DIR = PROJECT_ROOT / "web"
SECRETS_PATH = PROJECT_ROOT / ".autonovel-secrets.json"

PROCESSES: dict[str, asyncio.subprocess.Process] = {}

PROVIDERS: dict[str, dict[str, Any]] = {
    "openai": {
        "id": "openai",
        "name": "OpenAI",
        "base_url": "",
        "writer_model": "gpt-4o-mini",
        "reviewer_model": "gpt-4o-mini",
        "models": ["gpt-4o-mini", "gpt-4o", "gpt-5-mini"],
    },
    "opencode-go": {
        "id": "opencode-go",
        "name": "OpenCode Go",
        "base_url": "https://opencode.ai/zen/go/v1",
        "writer_model": "minimax-m2.7",
        "reviewer_model": "minimax-m2.7",
        "models": [
            "minimax-m2.7",
            "minimax-m2.5",
            "kimi-k2.6",
            "kimi-k2.5",
            "glm-5.1",
            "glm-5",
            "deepseek-v4-pro",
            "deepseek-v4-flash",
            "qwen3.6-plus",
            "qwen3.5-plus",
            "mimo-v2-pro",
            "mimo-v2-omni",
            "mimo-v2.5-pro",
            "mimo-v2.5",
            "hy3-preview",
        ],
    },
    "minimax": {
        "id": "minimax",
        "name": "MiniMax",
        "base_url": "https://api.minimax.io/v1",
        "writer_model": "MiniMax-M2.7",
        "reviewer_model": "MiniMax-M2.7",
        "models": [
            "MiniMax-M2.7",
            "MiniMax-M2.7-highspeed",
            "MiniMax-M2.5",
            "MiniMax-M2.5-highspeed",
            "MiniMax-M2.1",
            "MiniMax-M2.1-highspeed",
            "MiniMax-M2",
        ],
    },
    "deepseek": {
        "id": "deepseek",
        "name": "DeepSeek",
        "base_url": "https://api.deepseek.com",
        "writer_model": "deepseek-v4-pro",
        "reviewer_model": "deepseek-v4-pro",
        "models": ["deepseek-v4-pro", "deepseek-v4-flash"],
    },
}


class RunConfig(BaseModel):
    provider_id: str = "openai"
    openai_api_key: str | None = None
    openai_base_url: str | None = None
    fal_key: str | None = None
    elevenlabs_api_key: str | None = None
    writer_model: str = "gpt-4o"
    reviewer_model: str = "gpt-4o"
    seed_concept: str = Field(min_length=1)
    target_chapters: int = 2
    target_word_count: int = 6000
    foundation_threshold: float = 7.5
    chapter_threshold: float = 6.0
    voice_preferences: str = ""
    generate_cover: bool = False
    generate_audiobook: bool = False
    generate_pdf: bool = True


class ProviderKeyConfig(BaseModel):
    provider_id: str
    api_key: str = Field(min_length=1)


def _now() -> str:
    return datetime.now().isoformat()


def _run_dir(run_id: str) -> Path:
    return RUNS_DIR / run_id


def _manifest_path(run_id: str) -> Path:
    return _run_dir(run_id) / "manifest.json"


def _events_path(run_id: str) -> Path:
    return _run_dir(run_id) / "events.jsonl"


def _workspace_path(run_id: str) -> Path:
    return _run_dir(run_id) / "workspace"


def _load_secrets() -> dict[str, Any]:
    if not SECRETS_PATH.exists():
        return {"providers": {}}
    try:
        data = json.loads(SECRETS_PATH.read_text())
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=500, detail=f"Invalid local secrets file: {exc}") from exc
    if not isinstance(data, dict):
        return {"providers": {}}
    data.setdefault("providers", {})
    return data


def _write_secrets(data: dict[str, Any]):
    SECRETS_PATH.write_text(json.dumps(data, indent=2) + "\n")
    os.chmod(SECRETS_PATH, 0o600)


def _saved_provider_key(provider_id: str) -> str | None:
    provider = _load_secrets().get("providers", {}).get(provider_id, {})
    key = provider.get("api_key")
    return key if isinstance(key, str) and key else None


def _provider_payload(provider_id: str, provider: dict[str, Any]) -> dict[str, Any]:
    return {
        **provider,
        "has_saved_key": bool(_saved_provider_key(provider_id)),
    }


def _resolve_api_key(config: RunConfig) -> tuple[str, str]:
    runtime_key = (config.openai_api_key or "").strip()
    if runtime_key:
        return runtime_key, "runtime"
    saved_key = _saved_provider_key(config.provider_id)
    if saved_key:
        return saved_key, "saved"
    raise HTTPException(status_code=400, detail="API key is required. Paste one or save a key for this provider.")


def _redacted_config(config: RunConfig) -> dict[str, Any]:
    data = config.model_dump()
    data.pop("openai_api_key", None)
    if data.get("fal_key"):
        data["fal_key"] = "<provided>"
    if data.get("elevenlabs_api_key"):
        data["elevenlabs_api_key"] = "<provided>"
    return data


def _write_manifest(run_id: str, data: dict[str, Any]):
    path = _manifest_path(run_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, default=str))


def _load_manifest(run_id: str) -> dict[str, Any]:
    path = _manifest_path(run_id)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Run not found")
    return json.loads(path.read_text())


def _update_manifest(run_id: str, **updates: Any):
    manifest = _load_manifest(run_id)
    manifest.update(updates)
    manifest["updated_at"] = _now()
    _write_manifest(run_id, manifest)


def _ignore_workspace_entries(_: str, names: list[str]) -> set[str]:
    ignored = {
        ".git",
        ".venv",
        ".pytest_cache",
        "__pycache__",
        ".autonovel-secrets.json",
        ".env",
        "runs",
        "node_modules",
        "dist",
    }
    return {name for name in names if name in ignored or name.endswith(".pyc")}


def _copy_workspace(run_id: str, config: RunConfig):
    workspace = _workspace_path(run_id)
    shutil.copytree(PROJECT_ROOT, workspace, ignore=_ignore_workspace_entries)
    (workspace / "seed.txt").write_text(config.seed_concept.strip() + "\n")


def _artifact_tree(root: Path) -> list[dict[str, Any]]:
    if not root.exists():
        return []
    artifacts: list[dict[str, Any]] = []
    allowed_suffixes = {
        ".md",
        ".txt",
        ".json",
        ".jsonl",
        ".tsv",
        ".pdf",
        ".epub",
        ".png",
        ".jpg",
        ".jpeg",
        ".svg",
    }
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.name.startswith("."):
            continue
        if ".venv" in path.parts or "__pycache__" in path.parts:
            continue
        if path.suffix.lower() not in allowed_suffixes:
            continue
        rel = path.relative_to(root)
        artifacts.append({
            "path": str(rel),
            "size": path.stat().st_size,
            "modified_at": datetime.fromtimestamp(path.stat().st_mtime).isoformat(),
        })
    return artifacts


async def _watch_process(run_id: str, process: asyncio.subprocess.Process):
    stdout_task = asyncio.create_task(process.stdout.read() if process.stdout else _empty_bytes())
    stderr_task = asyncio.create_task(process.stderr.read() if process.stderr else _empty_bytes())
    returncode = await process.wait()
    stdout = (await stdout_task).decode(errors="replace")[-8000:]
    stderr = (await stderr_task).decode(errors="replace")[-8000:]
    status = "completed" if returncode == 0 else "failed"
    _update_manifest(
        run_id,
        status=status,
        finished_at=_now(),
        returncode=returncode,
        stdout_tail=stdout,
        stderr_tail=stderr,
    )
    PROCESSES.pop(run_id, None)


async def _empty_bytes() -> bytes:
    return b""


async def _start_run_process(run_id: str, config: RunConfig):
    workspace = _workspace_path(run_id)
    env = os.environ.copy()
    env.update({
        "OPENAI_API_KEY": config.openai_api_key,
        "WRITER_MODEL": config.writer_model,
        "REVIEWER_MODEL": config.reviewer_model,
        "AUTONOVEL_RUN_ID": run_id,
        "AUTONOVEL_RUN_DIR": str(_run_dir(run_id)),
        "AUTONOVEL_TARGET_CHAPTERS": str(config.target_chapters),
        "AUTONOVEL_TARGET_WORD_COUNT": str(config.target_word_count),
        "AUTONOVEL_FOUNDATION_THRESHOLD": str(config.foundation_threshold),
        "AUTONOVEL_CHAPTER_THRESHOLD": str(config.chapter_threshold),
        "AUTONOVEL_GENERATE_PDF": "1" if config.generate_pdf else "0",
        "AUTONOVEL_GENERATE_COVER": "1" if config.generate_cover else "0",
        "AUTONOVEL_GENERATE_AUDIOBOOK": "1" if config.generate_audiobook else "0",
    })
    if config.openai_base_url:
        env["OPENAI_BASE_URL"] = config.openai_base_url
    if config.fal_key:
        env["FAL_KEY"] = config.fal_key
    if config.elevenlabs_api_key:
        env["ELEVENLABS_API_KEY"] = config.elevenlabs_api_key

    process = await asyncio.create_subprocess_exec(
        "uv",
        "run",
        "python",
        "run_pipeline.py",
        "--from-scratch",
        "--target-chapters",
        str(config.target_chapters),
        "--target-word-count",
        str(config.target_word_count),
        "--foundation-threshold",
        str(config.foundation_threshold),
        "--chapter-threshold",
        str(config.chapter_threshold),
        *(["--no-pdf"] if not config.generate_pdf else []),
        *(["--generate-cover"] if config.generate_cover else []),
        *(["--generate-audiobook"] if config.generate_audiobook else []),
        cwd=workspace,
        env=env,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    PROCESSES[run_id] = process
    _update_manifest(run_id, status="running", pid=process.pid, started_at=_now())
    asyncio.create_task(_watch_process(run_id, process))


def create_app() -> FastAPI:
    app = FastAPI(title="Autonovel")

    assets = WEB_DIR / "assets"
    if assets.exists():
        app.mount("/assets", StaticFiles(directory=assets), name="assets")

    @app.get("/", response_class=HTMLResponse)
    async def index():
        index_path = WEB_DIR / "index.html"
        if not index_path.exists():
            raise HTTPException(status_code=500, detail="Web UI not built")
        return HTMLResponse(index_path.read_text(), headers={"Cache-Control": "no-store"})

    @app.get("/favicon.ico")
    async def favicon():
        return Response(status_code=204)

    @app.get("/api/providers")
    async def providers():
        return {"providers": [_provider_payload(provider_id, provider) for provider_id, provider in PROVIDERS.items()]}

    @app.post("/api/provider-keys")
    async def save_provider_key(config: ProviderKeyConfig):
        if config.provider_id not in PROVIDERS:
            raise HTTPException(status_code=400, detail="Unknown provider")
        data = _load_secrets()
        data.setdefault("providers", {})[config.provider_id] = {"api_key": config.api_key.strip()}
        _write_secrets(data)
        return {"providers": [_provider_payload(provider_id, provider) for provider_id, provider in PROVIDERS.items()]}

    @app.post("/api/runs")
    async def create_run(config: RunConfig):
        if config.provider_id not in PROVIDERS:
            raise HTTPException(status_code=400, detail="Unknown provider")
        provider = PROVIDERS[config.provider_id]
        resolved_key, key_source = _resolve_api_key(config)
        config = config.model_copy(update={
            "openai_api_key": resolved_key,
            "openai_base_url": config.openai_base_url if config.openai_base_url is not None else provider["base_url"],
        })
        run_id = datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8]
        run_dir = _run_dir(run_id)
        run_dir.mkdir(parents=True, exist_ok=False)
        _copy_workspace(run_id, config)
        manifest = {
            "id": run_id,
            "status": "queued",
            "created_at": _now(),
            "updated_at": _now(),
            "config": {**_redacted_config(config), "api_key_source": key_source},
            "events_path": str(_events_path(run_id)),
            "workspace_path": str(_workspace_path(run_id)),
        }
        _write_manifest(run_id, manifest)
        await _start_run_process(run_id, config)
        return _load_manifest(run_id)

    @app.get("/api/runs")
    async def list_runs():
        RUNS_DIR.mkdir(exist_ok=True)
        manifests = []
        for path in sorted(RUNS_DIR.glob("*/manifest.json"), reverse=True):
            manifests.append(json.loads(path.read_text()))
        return {"runs": manifests}

    @app.get("/api/runs/{run_id}")
    async def get_run(run_id: str):
        manifest = _load_manifest(run_id)
        return {
            "manifest": manifest,
            "artifacts": _artifact_tree(_workspace_path(run_id)),
        }

    @app.delete("/api/runs/{run_id}")
    async def stop_run(run_id: str):
        process = PROCESSES.get(run_id)
        if not process or process.returncode is not None:
            _update_manifest(run_id, status="stopped", stopped_at=_now())
            return {"status": "stopped"}
        process.terminate()
        try:
            await asyncio.wait_for(process.wait(), timeout=5)
        except asyncio.TimeoutError:
            process.kill()
        _update_manifest(run_id, status="stopped", stopped_at=_now())
        return {"status": "stopped"}

    @app.get("/api/runs/{run_id}/events")
    async def run_events(run_id: str):
        _load_manifest(run_id)
        events_path = _events_path(run_id)

        async def stream():
            position = 0
            while True:
                if events_path.exists():
                    with open(events_path) as f:
                        f.seek(position)
                        for line in f:
                            yield f"data: {line.rstrip()}\n\n"
                        position = f.tell()
                manifest = _load_manifest(run_id)
                if manifest.get("status") in {"completed", "failed", "stopped"}:
                    await asyncio.sleep(0.25)
                    if events_path.exists():
                        with open(events_path) as f:
                            f.seek(position)
                            for line in f:
                                yield f"data: {line.rstrip()}\n\n"
                    break
                await asyncio.sleep(1)

        return StreamingResponse(stream(), media_type="text/event-stream")

    @app.get("/api/runs/{run_id}/artifacts/{artifact_path:path}")
    async def artifact(run_id: str, artifact_path: str):
        _load_manifest(run_id)
        root = _workspace_path(run_id).resolve()
        path = (root / artifact_path).resolve()
        if not str(path).startswith(str(root)) or not path.exists() or not path.is_file():
            raise HTTPException(status_code=404, detail="Artifact not found")
        return FileResponse(path)

    return app


app = create_app()
