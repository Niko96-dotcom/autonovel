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
from fastapi.responses import FileResponse, HTMLResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RUNS_DIR = PROJECT_ROOT / "runs"
WEB_DIR = PROJECT_ROOT / "web"

PROCESSES: dict[str, asyncio.subprocess.Process] = {}


class RunConfig(BaseModel):
    openai_api_key: str = Field(min_length=1)
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
        return HTMLResponse(index_path.read_text())

    @app.post("/api/runs")
    async def create_run(config: RunConfig):
        run_id = datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8]
        run_dir = _run_dir(run_id)
        run_dir.mkdir(parents=True, exist_ok=False)
        _copy_workspace(run_id, config)
        manifest = {
            "id": run_id,
            "status": "queued",
            "created_at": _now(),
            "updated_at": _now(),
            "config": _redacted_config(config),
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

