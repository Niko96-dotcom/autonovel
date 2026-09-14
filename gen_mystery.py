#!/usr/bin/env python3
"""Generate author-only secrets and reveals from the current book foundation."""

import os
import sys

from dotenv import load_dotenv

from book_config import BASE_DIR, load_seed
from llm_client import call_llm

load_dotenv(BASE_DIR / ".env")
WRITER_MODEL = os.environ.get("AUTONOVEL_WRITER_MODEL", "claude-sonnet-4-6")


def main():
    seed = load_seed()
    world = (BASE_DIR / "world.md").read_text()
    characters = (BASE_DIR / "characters.md").read_text()
    prompt = f"""Create the author-only secrets and reveal plan for this novel.

STORY SEED:
{seed}

WORLD:
{world}

CHARACTERS:
{characters}

Write MYSTERY.md. Begin with '# Secrets & Reveals — Author Eyes Only'. Include:
- the central dramatic question and its true answer;
- character secrets and hidden motives;
- who knows each truth at the beginning;
- reveal timing by approximate chapter or percentage;
- concrete clues that can be planted without giving the answer away;
- red herrings only when fair;
- the final choice and its irreversible cost;
- unresolved questions that should remain deliberate.

Do not force a mystery genre onto the book. For romance, literary fiction, or other genres,
treat 'secrets' as withheld emotional or situational truths. Do not contradict the seed."""
    result = call_llm(
        prompt,
        model=WRITER_MODEL,
        max_tokens=8_000,
        temperature=0.45,
        system="You are a developmental editor who designs fair, story-specific reveals. Output Markdown only.",
        timeout=300,
    ).strip()
    path = BASE_DIR / "MYSTERY.md"
    path.write_text(result + "\n")
    print(f"Saved {path.name} ({len(result.split())} words)", file=sys.stderr)
    print(result)


if __name__ == "__main__":
    main()
