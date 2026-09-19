"""Parse guardrails and vocabulary wells from the current voice.md."""
from __future__ import annotations

import re
from pathlib import Path

WELL_KEYS = ("musical", "trade", "body")

_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)
_PART2_RE = re.compile(r"^##\s+Part\s+2\b", re.I | re.M)
_BULLET_RE = re.compile(r"^[-*]\s+(.*)$")
_FENCE_RE = re.compile(r"```([^\n]*)\n(.*?)```", re.S)
_HEADING_RE = re.compile(r"^#{1,6}\s+(.*)$")
_WELL_LINE_RE = re.compile(
    r"^(?:[-*]|\d+[.)])?\s*(?:\*\*)?(musical|music|trade|craft|body)"
    r"(?:\s+well|\s+lexicon)?(?:\*\*)?\s*[:—–-]\s+(.*)$",
    re.I,
)
_WELL_HEADING_RE = re.compile(
    r"(?i)\b(musical|music|trade|craft|body)\s+(well|lexicon|vocabulary|register)\b"
    r"|\b(well|lexicon|vocabulary)\s+(musical|music|trade|craft|body)\b"
    r"|\bwell[-_ ](musical|music|trade|craft|body)\b"
)
_WELL_INFO_RE = re.compile(
    r"(?i)(?:^|[-_\s])(musical|music|trade|craft|body)(?:[-_\s]|$)"
)
_TOKEN_RE = re.compile(r"[A-Za-z][A-Za-z'-]*")
_ALIAS = {
    "musical": "musical",
    "music": "musical",
    "trade": "trade",
    "craft": "trade",
    "body": "body",
}
_STOP = {
    "the", "a", "an", "and", "or", "from", "with", "for", "to", "of", "in",
    "on", "well", "wells", "vocabulary", "lexicon", "register",
}
_BOILERPLATE = re.compile(
    r"(?i)^(everything below|the agent proposes|generated during|"
    r"these are the|this file has|could be anything|the voice emerges|"
    r"not rules|the word-hoard|what does this world)"
)


def split_voice_parts(text: str) -> tuple[str, str]:
    match = _PART2_RE.search(text)
    if not match:
        return text, ""
    return text[: match.start()], text[match.start() :]


def _clean_rule(text: str) -> str:
    text = re.sub(r"\s+", " ", text.replace("**", "")).strip()
    return text


def _empty_wells() -> dict[str, set[str]]:
    return {key: set() for key in WELL_KEYS}


def _unfold(text: str) -> list[str]:
    lines: list[str] = []
    for raw in text.splitlines():
        if (
            lines
            and raw[:1] in " \t"
            and raw.strip()
            and not raw.lstrip().startswith(("#", "-", "*", "|"))
        ):
            lines[-1] = f"{lines[-1].rstrip()} {raw.strip()}"
        else:
            lines.append(raw)
    return lines


def extract_rule_lines(text: str, short_prose: bool = False) -> list[str]:
    """Bullet lines, plus short Part 2 lines when asked."""
    text = _COMMENT_RE.sub("", text)
    rules: list[str] = []
    seen: set[str] = set()
    for raw in _unfold(text):
        line = raw.strip()
        if not line or line[0] in "#|" or set(line) <= {"-", "*"}:
            continue
        if line.startswith(">"):
            line = line.lstrip("> ").strip()
        bullet = _BULLET_RE.match(line)
        if bullet:
            rule = _clean_rule(bullet.group(1))
        elif (
            short_prose
            and 8 <= len(line) <= 180
            and not line.endswith(":")
            and (line[0].isupper() or line[0] in "\"'")
        ):
            if _BOILERPLATE.search(line):
                continue
            rule = _clean_rule(line)
        else:
            continue
        key = rule.lower()
        if not rule or key in seen:
            continue
        seen.add(key)
        rules.append(rule)
    return rules


def parse_voice_rules(text: str) -> list[str]:
    part1, part2 = split_voice_parts(text)
    return extract_rule_lines(part1, short_prose=False) + extract_rule_lines(
        part2, short_prose=True
    )


def _alias(name: str | None) -> str | None:
    if not name:
        return None
    return _ALIAS.get(name.lower())


def _tokens(fragment: str) -> set[str]:
    words = set()
    for raw in _TOKEN_RE.findall(fragment):
        word = raw.lower().strip("'")
        if len(word) > 1 and word not in _STOP:
            words.add(word)
    return words


def _list_words(fragment: str) -> set[str]:
    fragment = fragment.strip()
    if not fragment or fragment.startswith("#") or fragment.startswith("<!--"):
        return set()
    ticks = re.findall(r"`([^`]+)`", fragment)
    if ticks:
        words: set[str] = set()
        for tick in ticks:
            words.update(_tokens(tick))
        return words
    if re.search(r"[.!?]", fragment) and "," not in fragment:
        return set()
    return _tokens(fragment)


def _heading_well_key(title: str) -> str | None:
    match = _WELL_HEADING_RE.search(title)
    if not match:
        return None
    return _alias(next(g for g in match.groups() if g and g.lower() in _ALIAS))


def _info_well_key(info: str) -> str | None:
    match = _WELL_INFO_RE.search(info.replace("_", "-"))
    return _alias(match.group(1)) if match else None


def parse_vocabulary_wells(text: str) -> dict[str, set[str]]:
    """Word sets from labeled wells / fenced lists. Empty if voice.md defines none."""
    wells = _empty_wells()
    text = _COMMENT_RE.sub("", text)

    for match in _FENCE_RE.finditer(text):
        key = _info_well_key(match.group(1).strip())
        if key:
            wells[key].update(_tokens(match.group(2)))

    current: str | None = None
    for raw in text.splitlines():
        line = raw.strip()
        heading = _HEADING_RE.match(line)
        if heading:
            current = _heading_well_key(heading.group(1))
            continue
        labeled = _WELL_LINE_RE.match(line)
        if labeled:
            key = _alias(labeled.group(1))
            if key:
                wells[key].update(_list_words(labeled.group(2)))
            continue
        if current:
            wells[current].update(_list_words(line))
    return wells


def load_vocabulary_wells(path: Path | None) -> dict[str, set[str]]:
    if path is None or not path.exists():
        return _empty_wells()
    try:
        return parse_vocabulary_wells(path.read_text(encoding="utf-8"))
    except OSError:
        return _empty_wells()
