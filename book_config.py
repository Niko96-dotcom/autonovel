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


def voice_identity(voice: str) -> str:
    """Return Part 2 when present, otherwise the full voice document."""
    lines = voice.splitlines()
    for index, line in enumerate(lines):
        if "Part 2" in line:
            return "\n".join(lines[index:])
    return voice
