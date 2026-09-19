"""Shared, forgiving access to the book brief created by AutoNovel Studio."""

from __future__ import annotations

import json
import re
from pathlib import Path

BASE_DIR = Path(__file__).parent

DEFAULT_BOOK = {
    "title": "Untitled Novel",
    "author": "",
    "genre": "Fiction",
    "audience": "Adult",
    "pointOfView": "Third person limited",
    "tense": "Past tense",
    "targetWords": 80_000,
    "targetChapters": 24,
    "premise": "",
}


def load_book() -> dict:
    """Return book.json merged onto safe defaults."""
    path = BASE_DIR / "book.json"
    values = DEFAULT_BOOK.copy()
    if path.exists():
        try:
            candidate = json.loads(path.read_text())
            if isinstance(candidate, dict):
                values.update({key: value for key, value in candidate.items() if value is not None})
        except (OSError, json.JSONDecodeError):
            pass
    return values


def load_seed() -> str:
    path = BASE_DIR / "seed.txt"
    return path.read_text() if path.exists() else ""


def title() -> str:
    return str(load_book().get("title") or "Untitled Novel")


def target_chapters() -> int:
    try:
        return max(1, int(load_book().get("targetChapters", 24)))
    except (TypeError, ValueError):
        return 24


def target_words() -> int:
    try:
        return max(5_000, int(load_book().get("targetWords", 80_000)))
    except (TypeError, ValueError):
        return 80_000


def target_words_per_chapter() -> int:
    return max(1_200, round(target_words() / target_chapters()))


def chapter_numbers() -> list[int]:
    numbers = []
    for path in (BASE_DIR / "chapters").glob("ch_*.md"):
        match = re.fullmatch(r"ch_(\d+)\.md", path.name)
        if match:
            numbers.append(int(match.group(1)))
    return sorted(numbers)


# Same heading shape get_total_chapters counts: ### Ch N / ### Chapter N.
CHAPTER_HEADING_RE = re.compile(r"###\s*Ch(?:apter)?\s*(\d+)")
# Word-boundary Chapter/Ch/Ch. N — does not match "which 2" or "such 5".
CHAPTER_MENTION_RE = re.compile(r"\b(?:Chapter|Ch\.?)\s*(\d+)\b", re.IGNORECASE)


def extract_mentioned_chapters(text: str) -> list[int]:
    """Return chapter numbers mentioned as Chapter N, Ch N, or Ch. N."""
    if not isinstance(text, str):
        return []
    return [int(num) for num in CHAPTER_MENTION_RE.findall(text)]


def extract_outline_entry(outline_text: str, chapter_num: int) -> str:
    """Return one chapter's outline block, or '' if that heading is absent.

    Stops at the next ### Ch(apter) heading of any number, ## Foreshadowing, or EOF.
    """
    matches = list(CHAPTER_HEADING_RE.finditer(outline_text))
    chapter_num = int(chapter_num)
    for index, match in enumerate(matches):
        if int(match.group(1)) != chapter_num:
            continue
        start = match.start()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(outline_text)
        block = outline_text[start:end]
        foreshadow = re.search(r"## Foreshadowing", block)
        if foreshadow:
            block = block[: foreshadow.start()]
        return block.strip()
    return ""


def voice_identity(voice: str) -> str:
    """Return Part 2 when present, otherwise the full voice document."""
    lines = voice.splitlines()
    for index, line in enumerate(lines):
        if "Part 2" in line:
            return "\n".join(lines[index:])
    return voice
