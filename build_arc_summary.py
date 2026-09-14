#!/usr/bin/env python3
"""
Build a condensed arc summary for full-novel evaluation.
For each chapter: first 150 words, last 150 words, plus any dialogue.
Gives the reader panel enough to evaluate the ARC without 72k tokens.
"""
import os
import re
from pathlib import Path
from dotenv import load_dotenv
from book_config import chapter_numbers, load_book, load_seed
from llm_client import call_llm

BASE_DIR = Path(__file__).parent
load_dotenv(BASE_DIR / ".env")

WRITER_MODEL = os.environ.get("AUTONOVEL_WRITER_MODEL", "claude-sonnet-4-6")
CHAPTERS_DIR = BASE_DIR / "chapters"

def call_writer(prompt, max_tokens=4000):
    return call_llm(
        prompt,
        model=WRITER_MODEL,
        max_tokens=max_tokens,
        temperature=0.1,
        system="You summarize novel chapters precisely. State what HAPPENS, what CHANGES, and what QUESTIONS are left open. No evaluation. No praise. Just events and shifts.",
        timeout=120,
    )

def extract_key_passages(text):
    """Get opening, closing, and best dialogue from a chapter."""
    words = text.split()
    opening = ' '.join(words[:150])
    closing = ' '.join(words[-150:])
    
    # Extract dialogue lines
    dialogue = re.findall(r'["""]([^"""]{20,})["""]', text)
    # Pick up to 3 longest dialogue lines
    dialogue.sort(key=len, reverse=True)
    top_dialogue = dialogue[:3]
    
    return opening, closing, top_dialogue

def main():
    summaries = []
    chapters = chapter_numbers()
    if not chapters:
        raise SystemExit("No chapter files found.")

    for ch in chapters:
        path = CHAPTERS_DIR / f"ch_{ch:02d}.md"
        text = path.read_text()
        wc = len(text.split())
        opening, closing, dialogue = extract_key_passages(text)
        
        # Get a 100-word summary from the model
        summary = call_writer(
            f"Summarize this chapter in exactly 3 sentences. What happens, what changes, what question is left open.\n\nCHAPTER {ch}:\n{text}",
            max_tokens=200
        )
        
        entry = f"""### Chapter {ch} ({wc} words)
**Summary:** {summary}

**Opening:** {opening}...

**Closing:** ...{closing}

**Key dialogue:**
"""
        for d in dialogue:
            entry += f'> "{d}"\n\n'
        
        summaries.append(entry)
        print(f"Ch {ch}: summarized ({wc}w)")
    
    # Calculate total word count
    total_wc = sum(len((CHAPTERS_DIR / f"ch_{c:02d}.md").read_text().split()) for c in chapters)
    
    # Assemble
    book = load_book()
    full = f"""# {book['title']}
## Full-Arc Summary for Reader Panel

This document contains chapter summaries, opening/closing passages,
and key dialogue for all {len(chapters)} chapters. Total novel: {total_wc:,} words.

STORY SEED:
{load_seed()}

---

"""
    full += '\n---\n\n'.join(summaries)
    
    out_path = BASE_DIR / "arc_summary.md"
    out_path.write_text(full)
    print(f"\nSaved to {out_path} ({len(full.split())} words)")

if __name__ == "__main__":
    main()
