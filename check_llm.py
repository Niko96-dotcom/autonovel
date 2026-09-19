#!/usr/bin/env python3
"""Validate the configured text-model backend with a tiny real request."""

import os
import sys
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).parent
load_dotenv(BASE_DIR / ".env", override=True)

from llm_client import api_base_url, call_llm, configuration_error, provider


def main() -> int:
    error = configuration_error()
    if error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    model = os.environ.get("AUTONOVEL_WRITER_MODEL", "claude-sonnet-4-6").strip()
    if not model:
        print("ERROR: AUTONOVEL_WRITER_MODEL is empty", file=sys.stderr)
        return 1

    print(f"Backend: {provider()} at {api_base_url()}")
    print(f"Model: {model}")
    reply = call_llm(
        "Reply with exactly AUTONOVEL_LOCAL_OK and nothing else.",
        model=model,
        max_tokens=32,
        temperature=0,
        timeout=120,
    )
    print(f"Reply: {reply.strip()}")
    if "AUTONOVEL_LOCAL_OK" not in reply:
        print("ERROR: backend replied, but not with the expected marker", file=sys.stderr)
        return 2
    print("Text-model connection is ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
