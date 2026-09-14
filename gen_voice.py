#!/usr/bin/env python3
"""Generate the novel-specific Part 2 of voice.md from the book seed."""

import os
import sys
from pathlib import Path

from dotenv import load_dotenv

from book_config import BASE_DIR, load_book, load_seed
from llm_client import call_llm

load_dotenv(BASE_DIR / ".env")
WRITER_MODEL = os.environ.get("AUTONOVEL_WRITER_MODEL", "claude-sonnet-4-6")


def main():
    seed = load_seed()
    if not seed.strip():
        raise SystemExit("seed.txt is empty. Complete New Book Setup first.")
    book = load_book()
    voice_path = BASE_DIR / "voice.md"
    current = voice_path.read_text() if voice_path.exists() else "# Voice Profile\n"
    part_one = current.split("## Part 2:", 1)[0].rstrip()

    prompt = f"""Design the prose voice for this novel.

BOOK BRIEF:
{seed}

Genre: {book['genre']}
Audience: {book['audience']}
Requested POV: {book['pointOfView']}
Requested tense: {book['tense']}

Return only the novel-specific voice profile, beginning with this exact heading:
## Part 2: Voice Identity (generated per novel)

Include concrete sections for Tone, Sentence Rhythm, Vocabulary Register, POV and Tense,
Dialogue Conventions, 3-5 Exemplar Passages, and 2-3 Anti-Exemplars. Make decisions rather
than offering menus. The examples must fit this book's characters and world. Avoid imitation
of any living author and avoid generic praise or filler."""

    result = call_llm(
        prompt,
        model=WRITER_MODEL,
        max_tokens=8_000,
        temperature=0.6,
        system=(
            "You are a precise fiction voice designer. You translate a story brief into "
            "usable prose constraints and original examples. You write clean, direct prose."
        ),
        timeout=300,
    ).strip()
    voice_path.write_text(f"{part_one}\n\n---\n\n{result}\n")
    print(f"Saved {voice_path.name} ({len(result.split())} generated words)", file=sys.stderr)
    print(result)


if __name__ == "__main__":
    main()
