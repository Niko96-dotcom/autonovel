#!/usr/bin/env python3
"""
Draft a single chapter using the writer model.
Usage: python draft_chapter.py 1
"""
import os
import sys
from pathlib import Path
from dotenv import load_dotenv
from book_config import extract_outline_entry, load_book, load_seed, target_words_per_chapter
from llm_client import call_llm

BASE_DIR = Path(__file__).parent
load_dotenv(BASE_DIR / ".env")

WRITER_MODEL = os.environ.get("AUTONOVEL_WRITER_MODEL", "claude-sonnet-4-6")
CHAPTERS_DIR = BASE_DIR / "chapters"

def call_writer(prompt, max_tokens=16000):
    return call_llm(
        prompt,
        model=WRITER_MODEL,
        max_tokens=max_tokens,
        temperature=0.8,
        system=(
            "You are a literary fiction writer drafting a complete novel chapter. "
            "You follow the voice definition exactly. You hit every beat in the outline. "
            "You never use words from the banned list. You show, never tell emotions. "
            "Your prose is specific, sensory, grounded. Metaphors come from the character's "
            "experience. You vary sentence length. You trust the reader. "
            "You write the FULL chapter -- do not truncate, summarize, or skip ahead."
        ),
        timeout=600,
    )

def load_file(path):
    try:
        return Path(path).read_text()
    except FileNotFoundError:
        return ""

def extract_chapter_outline(outline_text, chapter_num):
    """Extract a specific chapter's outline entry."""
    return extract_outline_entry(outline_text, chapter_num) or "(not found)"

def extract_next_chapter_outline(outline_text, chapter_num):
    """Extract the next chapter's outline (just first few lines for continuity)."""
    next_entry = extract_chapter_outline(outline_text, chapter_num + 1)
    if next_entry == "(not found)":
        return "(final chapter)"
    lines = next_entry.split('\n')[:10]
    return '\n'.join(lines)

def main():
    chapter_num = int(sys.argv[1])
    book = load_book()
    seed = load_seed()
    chapter_target = target_words_per_chapter()
    
    # Load all context
    voice = load_file(BASE_DIR / "voice.md")
    world = load_file(BASE_DIR / "world.md")
    characters = load_file(BASE_DIR / "characters.md")
    outline = load_file(BASE_DIR / "outline.md")
    canon = load_file(BASE_DIR / "canon.md")
    
    # Chapter-specific context
    chapter_outline = extract_chapter_outline(outline, chapter_num)
    next_chapter = extract_next_chapter_outline(outline, chapter_num)
    
    # Previous chapter (if exists)
    prev_path = CHAPTERS_DIR / f"ch_{chapter_num - 1:02d}.md"
    if prev_path.exists():
        prev_text = prev_path.read_text()
        prev_tail = prev_text[-2000:] if len(prev_text) > 2000 else prev_text
    else:
        prev_tail = "(first chapter -- no previous)"
    
    prompt = f"""Write Chapter {chapter_num} of "{book['title']}".

BOOK BRIEF:
{seed}

VOICE DEFINITION (follow this exactly):
{voice}

THIS CHAPTER'S OUTLINE (hit every beat):
{chapter_outline}

NEXT CHAPTER'S OUTLINE (for continuity -- end this chapter so it flows into the next):
{next_chapter}

PREVIOUS CHAPTER'S ENDING (continue from here):
{prev_tail}

WORLD BIBLE (reference for worldbuilding details):
{world}

CHARACTER REGISTRY (reference for speech patterns and behavior):
{characters}

CANON (established hard facts -- violations are bugs):
{canon}

WRITING INSTRUCTIONS:
1. Write the COMPLETE chapter. Target approximately {chapter_target:,} words. Do not truncate or summarize.
2. Use {book['pointOfView']} and {book['tense']}. Follow the POV named for this chapter in the outline.
3. Hit ALL numbered beats from the outline in order.
4. Plant ALL foreshadowing elements listed under "Plants."
5. Show character-specific sensory detail grounded in the viewpoint character's body, work, and history.
6. Dialogue follows the speech patterns and knowledge limits in characters.md.
7. No banned words from voice.md Part 1 guardrails.
8. Avoid AI fiction tells: no "a sense of," no "couldn't help but feel," no automatic "eyes widened."
9. Vary sentence and paragraph length with intent.
10. Draw metaphors from the viewpoint character's own experience, never a generic thesaurus.
11. Trust the reader. Don't explain what scenes already demonstrate.
12. Start in scene, not with an exposition block. End on a live moment or changed condition.

PATTERNS TO AVOID (these have been flagged in previous chapters):
13. NO triadic sensory lists. Never "X. Y. Z." or "X and Y and Z" as three
    separate items in a row. Combine two, cut one, or restructure.
14. Avoid repetitive "did not [verb]" constructions. Convert negatives
    to active alternatives or just cut them.
15. NO "thought about [X]" constructions. Replace with: the thought
    itself as a fragment, a physical action, or dialogue.
16. NO "the way [X] did [Y]" as a simile connector more than twice per
    chapter. Use different simile structures or cut the comparison.
17. NO over-explaining after showing. If a scene demonstrates something,
    do not have the narrator restate it. Trust the scene.
18. NO section breaks (---) as rhythm crutches. Only use for genuine
    time/location jumps. Max 2 per chapter.
19. VARY paragraph length deliberately. Never more than 3 consecutive
    paragraphs of similar length. Include at least one 1-2 sentence
    paragraph and one 6+ sentence paragraph.
20. END the chapter differently from the adjacent chapters. Find the ending that belongs to THIS chapter.
21. INCLUDE at least one moment that surprises -- a character saying
    the wrong thing, an emotional beat arriving early or late, a detail
    that doesn't fit the expected pattern. Predictable excellence is
    still predictable.
22. FAVOR scene over summary. At least 70% of the chapter should be
    in-scene (moment by moment, with dialogue and action) rather than
    summary (narrator compressing time).
23. DIALOGUE should sound like speech, not prose. Characters should
    occasionally stumble, interrupt, trail off, or say something slightly wrong.

Write the chapter now. Full text, beginning to end.
"""

    print(f"Drafting Chapter {chapter_num}...", file=sys.stderr)
    result = call_writer(prompt)
    
    # Save
    CHAPTERS_DIR.mkdir(parents=True, exist_ok=True)
    out_path = CHAPTERS_DIR / f"ch_{chapter_num:02d}.md"
    out_path.write_text(result)
    print(f"Saved to {out_path}", file=sys.stderr)
    print(f"Word count: {len(result.split())}", file=sys.stderr)
    print(result)

if __name__ == "__main__":
    main()
