#!/usr/bin/env python3
"""Build book-specific LaTeX sources from every current chapter file."""

from __future__ import annotations

import re
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
CHAPTERS_DIR = BASE_DIR / "chapters"
OUT_DIR = BASE_DIR / "typeset"


def latex_escape(text: str) -> str:
    replacements = {
        "\\": r"\textbackslash{}",
        "&": r"\&",
        "%": r"\%",
        "$": r"\$",
        "#": r"\#",
        "_": r"\_",
        "{": r"\{",
        "}": r"\}",
        "~": r"\textasciitilde{}",
        "^": r"\textasciicircum{}",
    }
    return "".join(replacements.get(char, char) for char in text)


def md_to_latex(body: str) -> str:
    result = []
    for line in body.splitlines():
        stripped = line.strip()
        if stripped == "---":
            result.append(r"\scenebreak")
        elif not stripped:
            result.append("")
        else:
            escaped = latex_escape(line)
            escaped = re.sub(r"\*([^*]+)\*", r"\\textit{\1}", escaped)
            escaped = escaped.replace("—", "---").replace("–", "--")
            result.append(escaped)
    return "\n".join(result)


def chapter_paths() -> list[Path]:
    def number(path: Path) -> int:
        match = re.search(r"(\d+)", path.stem)
        return int(match.group(1)) if match else 0

    return sorted(CHAPTERS_DIR.glob("ch_*.md"), key=number)


def build_chapters() -> int:
    rendered = []
    for path in chapter_paths():
        text = path.read_text().strip()
        if not text:
            continue
        lines = text.splitlines()
        title = lines[0].lstrip("# ").strip()
        if ": " in title:
            title = title.split(": ", 1)[1]
        rendered.append(f"\\chapter{{{latex_escape(title)}}}\n\n{md_to_latex(chr(10).join(lines[1:]).strip())}\n")
        print(f"  {path.name}: {title}")
    (OUT_DIR / "chapters_content.tex").write_text("\n\\clearpage\n\n".join(rendered))
    return len(rendered)


def main() -> None:
    count = build_chapters()
    if count == 0:
        raise SystemExit("No chapter files found.")
    print(f"Wrote {count} chapters to typeset/chapters_content.tex")


if __name__ == "__main__":
    main()
