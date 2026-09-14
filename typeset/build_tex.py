#!/usr/bin/env python3
"""Build book-specific LaTeX sources from every current chapter file."""

from __future__ import annotations

import json
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


def load_book() -> dict:
    defaults = {"title": "Untitled Novel", "author": "", "genre": "Fiction"}
    path = BASE_DIR / "book.json"
    if path.exists():
        try:
            candidate = json.loads(path.read_text())
            if isinstance(candidate, dict):
                defaults.update(candidate)
        except (OSError, json.JSONDecodeError):
            pass
    return defaults


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


def build_document() -> None:
    book = load_book()
    title = latex_escape(str(book.get("title") or "Untitled Novel"))
    author = latex_escape(str(book.get("author") or ""))
    genre = latex_escape(str(book.get("genre") or "Fiction"))
    document = rf"""\documentclass[11pt,openany]{{book}}
\usepackage[paperwidth=5.5in,paperheight=8.5in,inner=0.85in,outer=0.65in,top=0.75in,bottom=0.85in,headheight=14pt]{{geometry}}
\usepackage{{fontspec}}
\setmainfont{{EB Garamond}}[Ligatures=TeX]
\usepackage{{microtype}}
\usepackage{{setspace}}
\setstretch{{1.12}}
\usepackage{{fancyhdr}}
\usepackage{{titlesec}}
\usepackage{{hyperref}}
\hypersetup{{pdftitle={{{title}}},pdfauthor={{{author}}},pdfsubject={{{genre} Novel}},hidelinks}}
\setlength{{\parindent}}{{1.5em}}
\setlength{{\parskip}}{{0pt}}
\newcommand{{\scenebreak}}{{\par\vspace{{0.6\baselineskip}}\noindent\hfil{{\small\symbol{{"2022}}\quad\symbol{{"2022}}\quad\symbol{{"2022}}}}\hfil\par\vspace{{0.6\baselineskip}}}}
\renewcommand{{\thechapter}}{{\Roman{{chapter}}}}
\titleformat{{\chapter}}[display]{{\normalfont\centering}}{{\vspace*{{1.2in}}\footnotesize\textsc{{chapter \thechapter}}}}{{4pt}}{{\Large\itshape}}[\vspace{{0.5in}}]
\pagestyle{{fancy}}
\fancyhf{{}}
\fancyhead[LE]{{\small\textsc{{{title}}}}}
\fancyhead[RO]{{\small\textit{{\leftmark}}}}
\fancyfoot[C]{{\thepage}}
\renewcommand{{\headrulewidth}}{{0pt}}
\begin{{document}}
\frontmatter
\thispagestyle{{empty}}
\begin{{center}}
\vspace*{{2in}}
{{\Huge\textsc{{{title}}}}}\\[0.6in]
{{\large\textit{{A Novel}}}}\\[1in]
{{\Large\textsc{{{author}}}}}
\end{{center}}
\clearpage
\mainmatter
\input{{typeset/chapters_content.tex}}
\end{{document}}
"""
    (OUT_DIR / "novel.tex").write_text(document)


if __name__ == "__main__":
    count = build_chapters()
    if count == 0:
        raise SystemExit("No chapter files found.")
    build_document()
    print(f"Wrote {count} chapters and book-specific typeset/novel.tex")
