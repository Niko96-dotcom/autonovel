#!/usr/bin/env python3
"""Generate world.md from the current Story Seed and voice."""

import os
import sys

from dotenv import load_dotenv

from book_config import BASE_DIR, load_book, load_seed, voice_identity
from llm_client import call_llm

load_dotenv(BASE_DIR / ".env")
WRITER_MODEL = os.environ.get("AUTONOVEL_WRITER_MODEL", "claude-sonnet-4-6")


def main():
    seed = load_seed()
    if not seed.strip():
        raise SystemExit("seed.txt is empty. Complete New Book Setup first.")
    book = load_book()
    voice_path = BASE_DIR / "voice.md"
    voice = voice_identity(voice_path.read_text() if voice_path.exists() else "")

    prompt = f"""Build the definitive world reference for this {book['genre']} novel.

STORY SEED:
{seed}

VOICE IDENTITY:
{voice}

Write WORLD.MD in Markdown. Adapt the sections to this story rather than assuming fantasy.
Cover the places and social systems the plot needs; relevant history and present tensions;
technology, magic, law, or other speculative systems when present; hard rules, costs,
limitations, and edge cases; factions and institutions; daily life and culture; sensory
signatures for important locations; travel and geography; and a final list of hard
consistency rules.

Requirements:
- Be concrete enough that a scene writer can make decisions without inventing contradictions.
- Trace consequences: every major system changes work, family, status, power, and daily life.
- Give any extraordinary capability at least as much limitation as power.
- Interconnect setting, conflict, character, and theme.
- Include only details useful to this particular story; no encyclopedic padding.
- Never overwrite an explicit choice in the Story Seed.
- Target 2,500-4,000 dense words. Output Markdown only."""

    result = call_llm(
        prompt,
        model=WRITER_MODEL,
        max_tokens=16_000,
        temperature=0.65,
        system=(
            "You are a genre-flexible world and setting designer. Every rule has a cost, "
            "every institution has beneficiaries and victims, and every location has a sensory identity. "
            "You avoid generic lore and AI filler."
        ),
        timeout=600,
    ).strip()
    path = BASE_DIR / "world.md"
    path.write_text(result + "\n")
    print(f"Saved {path.name} ({len(result.split())} words)", file=sys.stderr)
    print(result)


if __name__ == "__main__":
    main()
