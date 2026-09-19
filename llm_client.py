"""Shared LLM client for Anthropic and OpenAI-compatible backends.

All text-generation code in autonovel goes through :func:`call_llm`.  This
keeps the original Anthropic setup working while also supporting llama.cpp,
Ollama, LM Studio, vLLM, and other OpenAI-compatible servers.
"""

from __future__ import annotations

import json
import math
import os
import re
from pathlib import Path
from urllib.parse import urlparse

import httpx


ANTHROPIC_DEFAULT_BASE = "https://api.anthropic.com"
OPENAI_DEFAULT_BASE = "https://api.openai.com"
_LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1"}


class LLMConfigurationError(RuntimeError):
    """Raised when the configured LLM backend cannot be used safely."""


def provider() -> str:
    """Return ``anthropic`` or ``openai`` for the current environment."""
    configured = os.environ.get("AUTONOVEL_LLM_PROVIDER", "").strip().lower()
    if configured:
        if configured not in {"anthropic", "openai"}:
            raise LLMConfigurationError(
                "AUTONOVEL_LLM_PROVIDER must be 'anthropic' or 'openai'"
            )
        return configured

    base_url = os.environ.get("AUTONOVEL_API_BASE_URL", ANTHROPIC_DEFAULT_BASE)
    return "anthropic" if "anthropic.com" in base_url.lower() else "openai"


def api_base_url() -> str:
    default = ANTHROPIC_DEFAULT_BASE if provider() == "anthropic" else OPENAI_DEFAULT_BASE
    return os.environ.get("AUTONOVEL_API_BASE_URL", default).rstrip("/")


def _api_key() -> str:
    key_file = os.environ.get("AUTONOVEL_API_KEY_FILE", "").strip()
    if key_file and not key_file.startswith("keychain:"):
        path = Path(key_file).expanduser()
        try:
            key = path.read_text().strip()
        except OSError as exc:
            raise LLMConfigurationError(
                f"Could not read AUTONOVEL_API_KEY_FILE: {path}"
            ) from exc
        if key:
            return key

    direct = os.environ.get("AUTONOVEL_API_KEY", "").strip()
    if direct:
        return direct

    legacy_name = "ANTHROPIC_API_KEY" if provider() == "anthropic" else "OPENAI_API_KEY"
    return os.environ.get(legacy_name, "").strip()


def configuration_error() -> str | None:
    """Return a human-readable configuration error, or ``None`` when ready."""
    try:
        selected_provider = provider()
        base_url = api_base_url()
        key = _api_key()
    except LLMConfigurationError as exc:
        return str(exc)

    if not base_url:
        return "AUTONOVEL_API_BASE_URL is empty"
    if not key and not is_local_openai_backend():
        return (
            "No LLM API key configured. Set AUTONOVEL_API_KEY, "
            "AUTONOVEL_API_KEY_FILE, or "
            + ("ANTHROPIC_API_KEY" if selected_provider == "anthropic" else "OPENAI_API_KEY")
            + "."
        )
    return None


def is_local_openai_backend() -> bool:
    """Return whether the current backend is a loopback OpenAI-compatible server."""
    return (
        provider() == "openai"
        and urlparse(api_base_url()).hostname in _LOCAL_HOSTS
    )


def pipeline_timeouts() -> tuple[int, int]:
    """Return (tool, batch) subprocess timeouts for pipeline orchestration."""
    local = is_local_openai_backend()
    tool = int(os.environ.get("AUTONOVEL_TOOL_TIMEOUT", "1800" if local else "600"))
    batch = int(os.environ.get("AUTONOVEL_BATCH_TIMEOUT", "21600" if local else "1800"))
    return tool, batch


def context_window() -> int:
    """Configured model context window, used to prevent impossible requests."""
    default = 1_000_000 if provider() == "anthropic" else 32_768
    value = os.environ.get("AUTONOVEL_CONTEXT_SIZE", str(default))
    try:
        parsed = int(value)
    except ValueError as exc:
        raise LLMConfigurationError("AUTONOVEL_CONTEXT_SIZE must be an integer") from exc
    if parsed < 1_024:
        raise LLMConfigurationError("AUTONOVEL_CONTEXT_SIZE must be at least 1024")
    return parsed


def estimate_tokens(text: str) -> int:
    """Conservative tokenizer-free estimate suitable for context budgeting."""
    return max(1, math.ceil(len(text) / 3.5))


def prompt_fits_context(prompt: str, *, system: str = "", max_tokens: int = 0) -> bool:
    used = estimate_tokens(prompt) + estimate_tokens(system) + max_tokens + 256
    return used <= context_window()


def _extract_json_value(text: str, start: int):
    """Parse one JSON object/array starting at ``start``, or raise ValueError."""
    depth = 0
    in_string = False
    escape = False
    open_char = text[start]
    close_char = '}' if open_char == '{' else ']'
    for i in range(start, len(text)):
        c = text[i]
        if escape:
            escape = False
            continue
        if c == '\\' and in_string:
            escape = True
            continue
        if c == '"' and not escape:
            in_string = not in_string
            continue
        if in_string:
            continue
        if c == open_char:
            depth += 1
        elif c == close_char:
            depth -= 1
            if depth == 0:
                return json.loads(text[start:i + 1], strict=False)
    raise ValueError("Unbalanced JSON bracket in response")


def parse_json_response(text: str):
    """Extract JSON from a response that might have markdown fences or trailing text."""
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r'^```\w*\n?', '', text)
        text = re.sub(r'\n?```$', '', text)
    obj_start = text.find('{')
    arr_start = text.find('[')
    # Try each bracket start by position. Prefatory prose like "Thoughts [ok]"
    # fails first, then a later object succeeds; real array payloads still win
    # when '[' is the outermost value.
    attempts = sorted({index for index in (obj_start, arr_start) if index != -1})
    if not attempts:
        raise ValueError("No JSON object found in response")
    errors: list[Exception] = []
    for start in attempts:
        try:
            return _extract_json_value(text, start)
        except (json.JSONDecodeError, ValueError) as exc:
            errors.append(exc)
    try:
        return json.loads(text, strict=False)
    except json.JSONDecodeError:
        fixed = re.sub(r'(?<!\\)\n', '\\n', text)
        try:
            return json.loads(fixed, strict=False)
        except json.JSONDecodeError as exc:
            if errors:
                raise errors[0] from exc
            raise


def _endpoint(path: str) -> str:
    base = api_base_url()
    if base.endswith("/v1"):
        return f"{base}/{path.removeprefix('v1/')}"
    return f"{base}/{path}"


def _timeout(requested: float) -> float:
    override = os.environ.get("AUTONOVEL_REQUEST_TIMEOUT", "").strip()
    if override:
        try:
            return float(override)
        except ValueError as exc:
            raise LLMConfigurationError("AUTONOVEL_REQUEST_TIMEOUT must be numeric") from exc

    if is_local_openai_backend():
        return max(requested, 1_800.0)
    return requested


def _openai_headers(key: str) -> dict[str, str]:
    headers = {"Content-Type": "application/json"}
    if key:
        headers["Authorization"] = f"Bearer {key}"
    return headers


def _bounded_max_tokens(prompt: str, system: str, requested: int) -> int:
    available = context_window() - estimate_tokens(prompt) - estimate_tokens(system) - 256
    if available < 128:
        raise LLMConfigurationError(
            "Prompt is too large for AUTONOVEL_CONTEXT_SIZE. Use a shorter input "
            "or increase the backend context window."
        )
    return max(1, min(requested, available))


def call_llm(
    prompt: str,
    *,
    model: str,
    max_tokens: int = 4_000,
    temperature: float = 0.3,
    system: str = "",
    timeout: float = 300,
) -> str:
    """Call the configured backend and return the assistant's text response."""
    error = configuration_error()
    if error:
        raise LLMConfigurationError(error)

    key = _api_key()
    max_tokens = _bounded_max_tokens(prompt, system, max_tokens)

    if provider() == "anthropic":
        headers = {
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "context-1m-2025-08-07",
            "content-type": "application/json",
        }
        payload: dict[str, object] = {
            "model": model,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "messages": [{"role": "user", "content": prompt}],
        }
        if system:
            payload["system"] = system
        response = httpx.post(
            _endpoint("v1/messages"),
            headers=headers,
            json=payload,
            timeout=_timeout(timeout),
        )
        response.raise_for_status()
        blocks = response.json().get("content", [])
        text = "".join(
            block.get("text", "")
            for block in blocks
            if isinstance(block, dict) and block.get("type", "text") == "text"
        )
    else:
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})
        response = httpx.post(
            _endpoint("v1/chat/completions"),
            headers=_openai_headers(key),
            json={
                "model": model,
                "max_tokens": max_tokens,
                "temperature": temperature,
                "stream": False,
                "messages": messages,
            },
            timeout=_timeout(timeout),
        )
        response.raise_for_status()
        message = response.json()["choices"][0]["message"]
        content = message.get("content", "")
        if isinstance(content, list):
            text = "".join(
                part.get("text", "")
                for part in content
                if isinstance(part, dict)
            )
        else:
            text = content or ""

    if not text.strip():
        raise RuntimeError("The LLM backend returned an empty response")
    return text
