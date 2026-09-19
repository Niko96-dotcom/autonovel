#!/usr/bin/env python3
"""Batch draft chapters with quick slop fix and spot-check evals."""
import subprocess
import sys
import re
import json
import os
from pathlib import Path
from dotenv import load_dotenv
from book_config import chapter_numbers, target_chapters

BASE_DIR = Path(__file__).parent
load_dotenv(BASE_DIR / ".env", override=True)
MODEL_TOOL_TIMEOUT = int(os.environ.get("AUTONOVEL_TOOL_TIMEOUT", "1800"))


STATE_FILE = BASE_DIR / "state.json"


def run(cmd, timeout=MODEL_TOOL_TIMEOUT):
    r = subprocess.run(
        cmd, shell=True, capture_output=True, text=True, timeout=timeout,
        cwd=BASE_DIR,
    )
    return r.stdout + r.stderr, r.returncode


def run_python(args, timeout=MODEL_TOOL_TIMEOUT):
    r = subprocess.run(
        [sys.executable, *args],
        capture_output=True, text=True, timeout=timeout,
        cwd=BASE_DIR,
    )
    return r.stdout + r.stderr, r.returncode

def slop_check(ch):
    script = (
        "from evaluate import slop_score, load_file; import json; "
        f"r=slop_score(load_file('chapters/ch_{ch:02d}.md')); print(json.dumps(r))"
    )
    out, _ = run_python(["-c", script])
    return json.loads(out.strip())

def pattern_check(ch):
    out, _ = run(f"grep -c 'He did not\\|He had not' chapters/ch_{ch:02d}.md")
    didnot = int(out.strip()) if out.strip().isdigit() else 0
    out, _ = run(f"grep -c 'He thought about\\|He thought of' chapters/ch_{ch:02d}.md")
    thought = int(out.strip()) if out.strip().isdigit() else 0
    out, _ = run(f"wc -w < chapters/ch_{ch:02d}.md")
    words = int(out.strip())
    return words, didnot, thought

def spot_eval(ch):
    out, rc = run_python(["evaluate.py", f"--chapter={ch}"])
    m_overall = re.search(r'overall_score: ([\d.]+)', out)
    m_raw = re.search(r'raw_judge_score: (\d+)', out)
    if m_overall and m_raw:
        return float(m_overall.group(1)), int(m_raw.group(1))
    return None, None


def chapters_to_draft():
    existing = chapter_numbers()
    if existing:
        return existing
    return list(range(1, target_chapters() + 1))


def spot_check_set(chapters):
    if not chapters:
        return set()
    n = len(chapters)
    return {chapters[i] for i in {n // 2, (2 * n) // 3, (5 * n) // 6, n - 1}}


def main():
    chapters = chapters_to_draft()
    spot_check_chapters = spot_check_set(chapters)
    results = []

    for ch in chapters:
        print(f"\n{'='*50}")
        print(f"DRAFTING CH {ch}")
        print(f"{'='*50}")
        
        # Draft
        out, rc = run_python(["draft_chapter.py", str(ch)])
        if rc != 0:
            print(f"  DRAFT FAILED: {out[:200]}")
            results.append((ch, 0, 0, "FAILED"))
            continue
        
        # Word count and patterns
        words, didnot, thought = pattern_check(ch)
        slop = slop_check(ch)
        
        print(f"  Words: {words}")
        print(f"  Slop penalty: {slop['slop_penalty']}")
        print(f"  Tier1: {len(slop['tier1_hits'])}  Fiction: {len(slop['fiction_ai_tells'])}  Telling: {slop['telling_violations']}")
        print(f"  Patterns: didnot={didnot} thought={thought}")
        
        # Spot-check eval on selected chapters
        score = None
        if ch in spot_check_chapters:
            print(f"  === SPOT-CHECK EVAL ===")
            score, raw = spot_eval(ch)
            if score is not None:
                print(f"  Score: {score} (raw {raw})")
                if score < 6.0:
                    print(f"  *** BELOW THRESHOLD -- flagging for retry ***")
            else:
                print(f"  Eval parse failed")
        
        results.append((ch, words, slop['slop_penalty'], score))
        
        # Git commit
        run(f"git add chapters/ch_{ch:02d}.md state.json")
        
        # Update state.json
        with open(STATE_FILE) as f:
            state = json.load(f)
        state["current_focus"] = f"ch_{ch:02d}"
        state["chapters_drafted"] = ch
        with open(STATE_FILE, "w") as f:
            json.dump(state, f, indent=2)

    print(f"\n\n{'='*60}")
    print("BATCH DRAFTING COMPLETE")
    print(f"{'='*60}")
    total_words = 0
    for ch, words, penalty, score in results:
        status = f"score={score}" if score else "drafted"
        print(f"  Ch {ch:2d}: {words:5d}w  slop={penalty:.1f}  {status}")
        total_words += words
    print(f"\n  Total new words: {total_words}")
    print(f"  Chapters drafted: {len([r for r in results if r[1] > 0])}")


if __name__ == "__main__":
    main()
