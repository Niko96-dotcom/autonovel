#!/usr/bin/env python3
"""Generate a complete, book-specific outline.md."""

import os
import sys

from dotenv import load_dotenv

from book_config import (
    BASE_DIR,
    load_book,
    load_seed,
    target_chapters,
    target_words,
    target_words_per_chapter,
    voice_identity,
)
from llm_client import call_llm

load_dotenv(BASE_DIR / ".env")
WRITER_MODEL = os.environ.get("AUTONOVEL_WRITER_MODEL", "claude-sonnet-4-6")


def main():
    book = load_book()
    seed = load_seed()
    world = (BASE_DIR / "world.md").read_text()
    characters = (BASE_DIR / "characters.md").read_text()
    mystery = (BASE_DIR / "MYSTERY.md").read_text()
    voice = voice_identity((BASE_DIR / "voice.md").read_text())
    chapter_count = target_chapters()
    words = target_words()
    per_chapter = target_words_per_chapter()

    prompt = f"""Build a complete chapter outline for '{book['title']}', a {book['genre']} novel.
Target exactly {chapter_count} chapters and approximately {words:,} words total
(about {per_chapter:,} words per chapter). Use {book['pointOfView']} and {book['tense']}.

STORY SEED:
{seed}

AUTHOR-ONLY SECRETS AND REVEALS:
{mystery}

WORLD:
{world}

CHARACTERS:
{characters}

VOICE:
{voice}

Start with '# {book['title']}' and a concise structure overview. Then provide exactly
{chapter_count} entries using the heading form '### Ch N: Title'. Every entry must state:
POV, location, approximate percentage, target word count, starting and ending emotion,
try-fail cycle, 3-6 concrete scene beats, planted information, paid-off information,
character movement, what changes by the end, and the question pulling the reader onward.

After the chapters, include a Foreshadowing Ledger with every meaningful plant and payoff.
Build escalation that fits this book rather than mechanically imposing one genre template.
The opening must make a promise the ending transforms. The midpoint must change the
protagonist's approach. The climax must use earlier choices, rules, and costs—no new rescue
mechanism. Include quiet chapters where the emotional arc requires them. Preserve all
explicit Story Seed choices. Output Markdown only and do not stop before the final chapter."""

    result = call_llm(
        prompt,
        model=WRITER_MODEL,
        max_tokens=24_000,
        temperature=0.45,
        system=(
            "You are a novel architect. You produce complete, draftable outlines with causal "
            "beats, character movement, escalation, and earned plants and payoffs."
        ),
        timeout=900,
    ).strip()
    path = BASE_DIR / "outline.md"
    path.write_text(result + "\n")
    print(f"Saved {path.name} ({len(result.split())} words)", file=sys.stderr)
    print(result)


if __name__ == "__main__":
    main()
