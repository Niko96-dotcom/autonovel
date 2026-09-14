#!/usr/bin/env python3
"""
Deep manuscript review via the configured review model.

Sends the novel to the selected backend for dual-persona review:
  1. Literary critic (newspaper book review style)
  2. Professor of fiction (specific, actionable craft suggestions)

Usage:
  python review.py                    # Review, save to edit_logs/
  python review.py --output reviews.md  # Also save human-readable copy
  python review.py --parse            # Parse last review into actionable items
"""
import os
import sys
import json
import re
import argparse
from pathlib import Path
from datetime import datetime
from dotenv import load_dotenv
from llm_client import (
    call_llm,
    configuration_error,
    prompt_fits_context,
)

BASE_DIR = Path(__file__).parent
load_dotenv(BASE_DIR / ".env", override=True)

REVIEW_MODEL = os.environ.get("AUTONOVEL_REVIEW_MODEL", "claude-opus-4-6")

CHAPTERS_DIR = BASE_DIR / "chapters"
LOGS_DIR = BASE_DIR / "edit_logs"

REVIEW_PROMPT = """Read the below novel, "{title}". Review it first as a literary critic (like a newspaper book review) and then as a professor of fiction. In the later review, give specific, actionable suggestions for any defects you find. Be fair but honest. You don't *have* to find defects.

{manuscript}"""

REVIEW_SYSTEM = (
    "You are a rigorous literary critic and professor of fiction. Read closely, "
    "distinguish evidence from inference, quote only text actually supplied, and make "
    "specific editorial recommendations."
)

SECTION_REVIEW_PROMPT = """You are reviewing one contiguous section of the novel "{title}".
This is section {section_number} of {section_count}, covering {chapter_names}.

Read it closely and produce evidence for a later whole-book review. Address:
- prose and voice strengths or failures, with short exact quotations
- character movement and inconsistencies
- pacing, repetition, missing transitions, and structural problems
- planted/payoff threads visible in this section
- the three most important actionable revisions

Do not pretend you have read chapters outside this section. Do not give a final star
rating. Label every observation with its chapter.

SECTION TEXT:
{section_text}"""

SYNTHESIS_REVIEW_PROMPT = """Produce the final review of "{title}" from the close-reading
reports below. Reconcile contradictions between reports and preserve chapter references.

Write two explicit sections:

1. LITERARY CRITIC REVIEW
Give a fair newspaper-style review and a rating written as "N/5".

2. PROFESSOR OF FICTION REVIEW
Give a numbered list of specific, actionable defects. Each item needs a short title,
severity, supporting chapter evidence, and a concrete revision. Do not invent quotations.
If the reports do not establish something, say so.

CLOSE-READING REPORTS:
{section_reviews}"""


def call_reviewer(prompt, max_tokens=8000):
    """Call the configured review model."""
    print(f"Sending to {REVIEW_MODEL} ({len(prompt):,} chars)...", file=sys.stderr)
    return call_llm(
        prompt,
        model=REVIEW_MODEL,
        max_tokens=max_tokens,
        temperature=0.3,
        system=REVIEW_SYSTEM,
        timeout=600,
    )


def build_review_chunks():
    """Group complete chapters into requests that fit the configured context."""
    chapters = sorted(CHAPTERS_DIR.glob("ch_*.md"))
    chunks = []
    current = []

    for chapter in chapters:
        candidate = current + [chapter]
        candidate_text = "\n\n---\n\n".join(path.read_text() for path in candidate)
        probe = SECTION_REVIEW_PROMPT.format(
            title=get_title(),
            section_number=1,
            section_count=1,
            chapter_names=", ".join(path.stem for path in candidate),
            section_text=candidate_text,
        )
        if current and not prompt_fits_context(
            probe,
            system=REVIEW_SYSTEM,
            max_tokens=2_500,
        ):
            chunks.append(current)
            current = [chapter]
        else:
            current = candidate

    if current:
        chunks.append(current)
    return chunks


def review_manuscript(title, manuscript):
    """Use one request when possible, otherwise close-read chunks then synthesize."""
    prompt = REVIEW_PROMPT.format(title=title, manuscript=manuscript)
    if prompt_fits_context(prompt, system=REVIEW_SYSTEM, max_tokens=8_000):
        return call_reviewer(prompt)

    chunks = build_review_chunks()
    reports = []
    for index, paths in enumerate(chunks, start=1):
        names = ", ".join(path.stem for path in paths)
        print(f"Review pass {index}/{len(chunks)}: {names}", file=sys.stderr)
        section_text = "\n\n---\n\n".join(path.read_text() for path in paths)
        section_prompt = SECTION_REVIEW_PROMPT.format(
            title=title,
            section_number=index,
            section_count=len(chunks),
            chapter_names=names,
            section_text=section_text,
        )
        report = call_reviewer(section_prompt, max_tokens=2_500)
        reports.append(f"## Section {index}: {names}\n{report}")

    synthesis_prompt = SYNTHESIS_REVIEW_PROMPT.format(
        title=title,
        section_reviews="\n\n".join(reports),
    )
    return call_reviewer(synthesis_prompt)


def get_title():
    """Extract novel title from first chapter or outline."""
    outline = BASE_DIR / "outline.md"
    if outline.exists():
        first_line = outline.read_text().split("\n")[0]
        title = first_line.lstrip("# ").strip()
        if title:
            return title
    ch1 = CHAPTERS_DIR / "ch_01.md"
    if ch1.exists():
        first_line = ch1.read_text().split("\n")[0]
        return first_line.lstrip("# ").strip()
    return "Untitled Novel"


def build_manuscript():
    """Concatenate all chapters into a single text."""
    chapters = sorted(CHAPTERS_DIR.glob("ch_*.md"))
    if not chapters:
        print("ERROR: No chapters found.", file=sys.stderr)
        sys.exit(1)
    
    parts = []
    for ch in chapters:
        parts.append(ch.read_text())
    
    manuscript = "\n\n---\n\n".join(parts)
    wc = len(manuscript.split())
    print(f"Manuscript: {len(chapters)} chapters, {wc:,} words", file=sys.stderr)
    return manuscript


def parse_review(review_text):
    """Parse a review into structured actionable items."""
    items = []
    
    # Split into critic and professor sections
    sections = re.split(
        r'professor.*?(?:review|assessment|analysis|craft)',
        review_text,
        maxsplit=1,
        flags=re.IGNORECASE,
    )
    
    critic_text = sections[0] if sections else review_text
    professor_text = sections[1] if len(sections) > 1 else ""
    
    # Extract star rating
    star_match = re.search(
        r'(?P<symbols>★+)(?P<half>½)?|'
        r'(?P<number>\d+(?:\.\d+)?)\s*/?\s*(?:out of\s*)?(?:five|5)',
        critic_text,
        re.IGNORECASE,
    )
    stars = None
    if star_match:
        if star_match.group("number"):
            stars = float(star_match.group("number"))
        else:
            stars = len(star_match.group("symbols")) + (
                0.5 if star_match.group("half") else 0
            )
    
    # Extract professor's numbered items
    # Look for patterns like "1. Title" or "Problem:" or "Suggestion:"
    prof_items = re.split(r'\n(?=\d+\.\s+[A-Z])', professor_text)
    
    for section in prof_items:
        if not section.strip():
            continue
        
        # Extract the item title/number
        title_match = re.match(r'(\d+)\.\s+(.+?)(?:\n|$)', section)
        if not title_match:
            continue
        
        num = int(title_match.group(1))
        title = title_match.group(2).strip()
        
        # Classify severity based on language
        text_lower = section.lower()
        if any(w in text_lower for w in ['major', 'significant', 'primary', 'most important']):
            severity = "major"
        elif any(w in text_lower for w in ['minor', 'small', 'slight', 'cosmetic']):
            severity = "minor"
        else:
            severity = "moderate"
        
        # Classify type
        if any(w in text_lower for w in ['cut', 'compress', 'trim', 'reduce', 'consolidate']):
            fix_type = "compression"
        elif any(w in text_lower for w in ['add', 'expand', 'introduce', 'give', 'more']):
            fix_type = "addition"  
        elif any(w in text_lower for w in ['repetit', 'recurring', 'frequency', 'tic', 'gesture']):
            fix_type = "mechanical"
        elif any(w in text_lower for w in ['restructur', 'rearrang', 'move', 'reorganiz']):
            fix_type = "structural"
        else:
            fix_type = "revision"
        
        # Check if this is qualified/hedged (diminishing returns signal)
        qualified = any(phrase in text_lower for phrase in [
            'individually fine', 'largely successful', 'each instance works',
            'minor relative to', 'small complaint', 'costs of ambition',
            'not a flaw', 'deliberate choice', 'thematically coherent'
        ])
        
        # Extract specific suggestion
        suggestion = ""
        sugg_match = re.search(r'(?:Specific\s+)?[Ss]uggestion[s]?:?\s*\n?(.*?)(?=\n\d+\.|\n\n[A-Z]|\Z)', 
                               section, re.DOTALL)
        if sugg_match:
            suggestion = sugg_match.group(1).strip()[:500]
        
        items.append({
            "number": num,
            "title": title,
            "severity": severity,
            "type": fix_type,
            "qualified": qualified,
            "suggestion": suggestion,
            "full_text": section.strip()[:1000],
        })
    
    return {
        "stars": stars,
        "critic_summary": critic_text.strip()[:500],
        "professor_items": items,
        "total_items": len(items),
        "major_items": sum(1 for i in items if i["severity"] == "major"),
        "qualified_items": sum(1 for i in items if i["qualified"]),
        "raw_text": review_text,
    }


def should_stop(parsed_review):
    """Determine if the novel is done being revised.
    
    Stopping conditions:
    - Stars >= 4
    - No major unqualified items
    - More than half the items are qualified/hedged
    """
    stars = parsed_review.get("stars", 0) or 0
    total = parsed_review["total_items"]
    major = parsed_review["major_items"]
    qualified = parsed_review["qualified_items"]
    
    if stars >= 4.5 and major == 0:
        return True, "★★★★½ with no major items"
    if stars >= 4 and total > 0 and qualified / total > 0.5:
        return True, f"★{'★' * int(stars)} with {qualified}/{total} items qualified"
    if total <= 2:
        return True, f"Only {total} items found"
    
    return False, f"{major} major items, {total - qualified} unqualified"


def cmd_review(args):
    """Generate a review."""
    title = get_title()
    manuscript = build_manuscript()
    
    review_text = review_manuscript(title, manuscript)
    
    # Save raw review
    LOGS_DIR.mkdir(exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_path = LOGS_DIR / f"{timestamp}_review.json"
    
    parsed = parse_review(review_text)
    parsed["timestamp"] = timestamp
    parsed["title"] = title
    parsed["word_count"] = len(manuscript.split())
    
    log_path.write_text(json.dumps(parsed, indent=2, default=str))
    print(f"\nReview saved to {log_path}", file=sys.stderr)
    
    # Save human-readable copy
    if args.output:
        Path(args.output).write_text(review_text)
        print(f"Human-readable copy: {args.output}", file=sys.stderr)
    
    # Print summary
    stop, reason = should_stop(parsed)
    print(f"\n{'='*50}")
    print(f"REVIEW SUMMARY")
    print(f"  Stars: {parsed['stars']}")
    print(f"  Items: {parsed['total_items']} ({parsed['major_items']} major)")
    print(f"  Qualified: {parsed['qualified_items']}/{parsed['total_items']}")
    print(f"  Stop revising? {'YES — ' + reason if stop else 'NO — ' + reason}")
    print(f"{'='*50}")
    
    return parsed


def cmd_parse(args):
    """Parse the most recent review into actionable items."""
    LOGS_DIR.mkdir(exist_ok=True)
    reviews = sorted(LOGS_DIR.glob("*_review.json"), reverse=True)
    if not reviews:
        print("No reviews found. Run: review.py first")
        sys.exit(1)
    
    latest = json.loads(reviews[0].read_text())
    
    print(f"Latest review: {latest.get('timestamp', 'unknown')}")
    print(f"Stars: {latest.get('stars', '?')}")
    print(f"\nACTIONABLE ITEMS ({latest['total_items']}):")
    
    for item in latest.get("professor_items", []):
        qual = " [QUALIFIED]" if item["qualified"] else ""
        print(f"\n  {item['number']}. [{item['severity'].upper()}] [{item['type']}]{qual}")
        print(f"     {item['title']}")
        if item["suggestion"]:
            print(f"     Suggestion: {item['suggestion'][:120]}...")
    
    stop, reason = should_stop(latest)
    print(f"\n{'='*50}")
    print(f"Stop revising? {'YES — ' + reason if stop else 'NO — ' + reason}")
    print(f"{'='*50}")


def main():
    parser = argparse.ArgumentParser(description="Deep manuscript review")
    parser.add_argument("--output", "-o", default=None, help="Save human-readable review to file")
    parser.add_argument("--parse", action="store_true", help="Parse most recent review")
    
    args = parser.parse_args()
    
    error = configuration_error()
    if error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
    
    if args.parse:
        cmd_parse(args)
    else:
        cmd_review(args)


if __name__ == "__main__":
    main()
