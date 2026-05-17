"""OpenAI-shaped LLM access for Autonovel.

This module is intentionally small: pipeline scripts pass OpenAI chat messages
in, and this layer handles BYOK credentials, base URL overrides, model slots,
streaming, and transient API retry behavior.
"""

from __future__ import annotations

import asyncio
import os
from collections.abc import AsyncIterator, Sequence
from typing import Any, Literal, overload

from openai import APIConnectionError, AsyncOpenAI, RateLimitError

Message = dict[str, str]
ModelSlot = Literal["writer", "reviewer"]

DEFAULT_WRITER_MODEL = "gpt-4o"
DEFAULT_REVIEWER_MODEL = "gpt-4o"
DEFAULT_MAX_RETRIES = 4
DEFAULT_RETRY_BASE_SECONDS = 1.0


class LLMConfigurationError(RuntimeError):
    """Raised when required BYOK configuration is missing."""


def writer_model(override: str | None = None) -> str:
    """Return the configured writer model."""
    return (
        override
        or os.environ.get("WRITER_MODEL")
        or DEFAULT_WRITER_MODEL
    )


def reviewer_model(override: str | None = None) -> str:
    """Return the configured reviewer model."""
    return (
        override
        or os.environ.get("REVIEWER_MODEL")
        or DEFAULT_REVIEWER_MODEL
    )


def model_for_slot(slot: ModelSlot = "writer", override: str | None = None) -> str:
    if slot == "reviewer":
        return reviewer_model(override)
    return writer_model(override)


def _api_key(runtime_api_key: str | None = None) -> str:
    api_key = runtime_api_key or os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise LLMConfigurationError(
            "OPENAI_API_KEY is required. Set it in the environment or pass a runtime API key."
        )
    return api_key


def _base_url(runtime_base_url: str | None = None) -> str | None:
    return runtime_base_url or os.environ.get("OPENAI_BASE_URL") or None


def _client(
    *,
    api_key: str | None = None,
    base_url: str | None = None,
) -> AsyncOpenAI:
    kwargs: dict[str, Any] = {"api_key": _api_key(api_key)}
    resolved_base_url = _base_url(base_url)
    if resolved_base_url:
        kwargs["base_url"] = resolved_base_url
    return AsyncOpenAI(**kwargs)


async def _sleep_before_retry(attempt: int, retry_base_seconds: float) -> None:
    await asyncio.sleep(retry_base_seconds * (2 ** attempt))


async def _stream_text(response: Any) -> AsyncIterator[str]:
    async for chunk in response:
        delta = chunk.choices[0].delta
        text = getattr(delta, "content", None)
        if text:
            yield text


async def _create_with_retries(
    *,
    client: AsyncOpenAI,
    payload: dict[str, Any],
    max_retries: int,
    retry_base_seconds: float,
) -> Any:
    last_error: Exception | None = None
    for attempt in range(max_retries + 1):
        try:
            return await client.chat.completions.create(**payload)
        except (RateLimitError, APIConnectionError) as exc:
            last_error = exc
            if attempt >= max_retries:
                break
            await _sleep_before_retry(attempt, retry_base_seconds)
    assert last_error is not None
    raise last_error


@overload
async def complete(
    messages: Sequence[Message],
    *,
    model: str,
    temperature: float = 0.7,
    max_tokens: int = 4000,
    response_format: dict[str, Any] | None = None,
    stream: Literal[False] = False,
    api_key: str | None = None,
    base_url: str | None = None,
    max_retries: int = DEFAULT_MAX_RETRIES,
    retry_base_seconds: float = DEFAULT_RETRY_BASE_SECONDS,
) -> str: ...


@overload
async def complete(
    messages: Sequence[Message],
    *,
    model: str,
    temperature: float = 0.7,
    max_tokens: int = 4000,
    response_format: dict[str, Any] | None = None,
    stream: Literal[True],
    api_key: str | None = None,
    base_url: str | None = None,
    max_retries: int = DEFAULT_MAX_RETRIES,
    retry_base_seconds: float = DEFAULT_RETRY_BASE_SECONDS,
) -> AsyncIterator[str]: ...


async def complete(
    messages: Sequence[Message],
    *,
    model: str,
    temperature: float = 0.7,
    max_tokens: int = 4000,
    response_format: dict[str, Any] | None = None,
    stream: bool = False,
    api_key: str | None = None,
    base_url: str | None = None,
    max_retries: int = DEFAULT_MAX_RETRIES,
    retry_base_seconds: float = DEFAULT_RETRY_BASE_SECONDS,
) -> str | AsyncIterator[str]:
    """Complete OpenAI chat messages and return text or an async text stream."""
    payload: dict[str, Any] = {
        "model": model,
        "messages": list(messages),
        "temperature": temperature,
        "max_tokens": max_tokens,
        "stream": stream,
    }
    if response_format is not None:
        payload["response_format"] = response_format

    client = _client(api_key=api_key, base_url=base_url)
    response = await _create_with_retries(
        client=client,
        payload=payload,
        max_retries=max_retries,
        retry_base_seconds=retry_base_seconds,
    )
    if stream:
        return _stream_text(response)
    return response.choices[0].message.content or ""


def complete_sync(
    messages: Sequence[Message],
    *,
    model: str,
    temperature: float = 0.7,
    max_tokens: int = 4000,
    response_format: dict[str, Any] | None = None,
    api_key: str | None = None,
    base_url: str | None = None,
    max_retries: int = DEFAULT_MAX_RETRIES,
    retry_base_seconds: float = DEFAULT_RETRY_BASE_SECONDS,
) -> str:
    """Synchronous wrapper for legacy scripts while the pipeline is migrated."""
    return asyncio.run(
        complete(
            messages,
            model=model,
            temperature=temperature,
            max_tokens=max_tokens,
            response_format=response_format,
            stream=False,
            api_key=api_key,
            base_url=base_url,
            max_retries=max_retries,
            retry_base_seconds=retry_base_seconds,
        )
    )


def complete_prompt_sync(
    prompt: str,
    *,
    system: str | None = None,
    slot: ModelSlot = "writer",
    model: str | None = None,
    temperature: float = 0.7,
    max_tokens: int = 4000,
    response_format: dict[str, Any] | None = None,
    api_key: str | None = None,
    base_url: str | None = None,
    max_retries: int = DEFAULT_MAX_RETRIES,
    retry_base_seconds: float = DEFAULT_RETRY_BASE_SECONDS,
) -> str:
    """Complete a single prompt using optional OpenAI system/user messages."""
    messages: list[Message] = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    return complete_sync(
        messages,
        model=model_for_slot(slot, model),
        temperature=temperature,
        max_tokens=max_tokens,
        response_format=response_format,
        api_key=api_key,
        base_url=base_url,
        max_retries=max_retries,
        retry_base_seconds=retry_base_seconds,
    )
