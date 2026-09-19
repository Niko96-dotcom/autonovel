#!/usr/bin/env python3
"""Generate characters.md from the current book seed and world."""

import os
import sys

from dotenv import load_dotenv

from book_config import BASE_DIR, load_book, load_seed, voice_identity
from llm_client import call_llm

load_dotenv(BASE_DIR / ".env")
WRITER_MODEL = os.environ.get("AUTONOVEL_WRITER_MODEL", "claude-sonnet-4-6")


def main():
    seed = load_seed()
    book = load_book()
    world = (BASE_DIR / "world.md").read_text()
    voice = voice_identity((BASE_DIR / "voice.md").read_text())

    prompt = f"""Build the definitive character registry for this {book['genre']} novel.

STORY SEED:
{seed}

WORLD:
{world}

VOICE:
{voice}

Write CHARACTERS.MD in Markdown. Identify the protagonist and every major character from
the source material, then add only supporting characters the story genuinely needs.

For each major character include: name, age or life stage, role, ghost/wound/lie/want/need,
proactivity/likability/competence sliders with short justification, contradictions, arc,
physical specificity, habits, knowledge limits, secrets, relationships, thematic function,
and an eight-dimension speech profile with two original example lines. Supporting characters
may be shorter but still need a goal and distinctive behavior.

Requirements:
- Start each character with a level-2 heading: `## Name (POV)` or `## Name (non-POV)`.
- Preserve names and identity choices supplied in the Story Seed.
- Make wants collide; no character exists only to deliver information.
- Give opposing characters defensible inner logic rather than making them generic villains.
- Dialogue samples must pass the no-tags test.
- State who knows each important fact at the beginning.
- Target 2,500-4,000 dense words. Output Markdown only."""

    result = call_llm(
        prompt,
        model=WRITER_MODEL,
        max_tokens=16_000,
        temperature=0.65,
        system=(
            "You design psychologically specific fictional characters with conflicting wants, "
            "distinct speech, agency, secrets, and behavior. You never use generic praise or AI filler."
        ),
        timeout=600,
    ).strip()
    path = BASE_DIR / "characters.md"
    path.write_text(result + "\n")
    print(f"Saved {path.name} ({len(result.split())} words)", file=sys.stderr)
    print(result)


if __name__ == "__main__":
    main()
