#!/usr/bin/env python3
"""Extract canon.md from the current book foundation."""

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
    outline = (BASE_DIR / "outline.md").read_text()
    prompt = f"""Extract the checkable canon for this novel. Do not invent facts.

STORY SEED:
{seed}

WORLD:
{world}

CHARACTERS:
{characters}

OUTLINE:
{outline}

Write CANON.MD in Markdown. Use one atomic, testable fact per bullet under sections for
Character Facts, Relationships and Knowledge, Geography and Travel, Timeline, Systems and
Rules, Objects and Resources, Factions and Institutions, Established Events, and Hard
Continuity Constraints. Add source labels such as [Seed], [World], [Characters], or
[Outline Ch 4] where practical. Record uncertainty explicitly instead of resolving it.
Do not turn themes, intentions, or proposed possibilities into facts. Output Markdown only."""
    result = call_llm(
        prompt,
        model=WRITER_MODEL,
        max_tokens=16_000,
        temperature=0.15,
        system=(
            "You are a continuity editor. You extract precise atomic facts from source "
            "documents and never fill gaps by guessing."
        ),
        timeout=600,
    ).strip()
    path = BASE_DIR / "canon.md"
    path.write_text(result + "\n")
    print(f"Saved {path.name} ({len(result.split())} words)", file=sys.stderr)
    print(result)


if __name__ == "__main__":
    main()
