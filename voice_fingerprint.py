#!/usr/bin/env python3
"""
Voice fingerprint: quantitative analysis of prose across all chapters.
Measures the things the voice doc says SHOULD be true and checks if they ARE.

Outputs: voice_fingerprint.json with per-chapter metrics.
"""
import re
import json
import statistics
from pathlib import Path
from collections import Counter
from book_config import chapter_numbers
from voice_parse import load_vocabulary_wells

BASE_DIR = Path(__file__).parent
CHAPTERS_DIR = BASE_DIR / "chapters"

# Abstract vs concrete noun indicators
ABSTRACT_INDICATORS = {
    "sense", "feeling", "notion", "concept", "idea", "quality",
    "nature", "essence", "aspect", "element", "factor", "presence",
    "absence", "weight", "gravity", "meaning", "significance",
    "implication", "possibility", "certainty", "uncertainty",
    "awareness", "consciousness", "realization", "understanding",
}

def analyze_chapter(path, wells=None):
    text = path.read_text()
    words = text.split()
    word_count = len(words)
    lower_words = [w.lower().strip(".,;:!?\"'()—-–") for w in words]
    if wells is None:
        wells = load_vocabulary_wells(BASE_DIR / "voice.md")
    
    # Sentence analysis
    sentences = re.split(r'[.!?]+', text)
    sentences = [s.strip() for s in sentences if len(s.strip().split()) > 2]
    sent_lengths = [len(s.split()) for s in sentences]
    
    # Paragraph analysis
    paragraphs = [p.strip() for p in text.split('\n\n') if p.strip() and not p.strip().startswith('#') and p.strip() != '---']
    para_lengths = [len(p.split()) for p in paragraphs]
    
    # Vocabulary well counts (word sets come from the current voice.md)
    musical_count = sum(1 for w in lower_words if w in wells["musical"])
    trade_count = sum(1 for w in lower_words if w in wells["trade"])
    body_count = sum(1 for w in lower_words if w in wells["body"])
    well_hits = musical_count + trade_count + body_count
    total_well = well_hits or 1
    
    # Abstract noun density
    abstract_count = sum(1 for w in lower_words if w in ABSTRACT_INDICATORS)
    
    # Dialogue analysis
    dialogue_matches = re.findall(r'["""][^"""]*["""]|[\'"][^\'"]*[\'"]', text)
    # Better: count lines with speech marks
    dialogue_words = sum(len(m.split()) for m in dialogue_matches)
    dialogue_ratio = dialogue_words / word_count if word_count > 0 else 0
    
    # Em-dash count
    em_dashes = text.count('—') + text.count('--')
    em_per_1k = (em_dashes / word_count) * 1000 if word_count > 0 else 0
    
    # Section breaks
    section_breaks = text.count('\n---\n') + text.count('\n\n---\n\n')
    
    # Sentence starters (check for repetitive He/She/The)
    starters = []
    for s in sentences:
        first = s.strip().split()[0] if s.strip().split() else ""
        starters.append(first)
    starter_counts = Counter(starters)
    he_starts = starter_counts.get("He", 0) + starter_counts.get("he", 0)
    he_start_pct = he_starts / len(sentences) * 100 if sentences else 0
    
    # "the way" simile count
    the_way_count = len(re.findall(r'\bthe way\b', text, re.IGNORECASE))
    
    # Fragment count (sentences under 5 words)
    fragments = sum(1 for l in sent_lengths if l < 5)
    long_sents = sum(1 for l in sent_lengths if l > 30)
    
    # Metaphor/simile density (rough: count "like" and "as" comparisons)
    like_count = len(re.findall(r'\blike\s+(?:a|an|the)\b', text))
    as_count = len(re.findall(r'\bas\s+(?:a|an|the|if|though)\b', text))
    
    return {
        "word_count": word_count,
        "sentence_count": len(sentences),
        "paragraph_count": len(paragraphs),
        "avg_sentence_length": round(statistics.mean(sent_lengths), 1) if sent_lengths else 0,
        "sentence_length_std": round(statistics.stdev(sent_lengths), 1) if len(sent_lengths) > 1 else 0,
        "sentence_length_cv": round(statistics.stdev(sent_lengths) / statistics.mean(sent_lengths), 3) if sent_lengths and statistics.mean(sent_lengths) > 0 else 0,
        "min_sentence": min(sent_lengths) if sent_lengths else 0,
        "max_sentence": max(sent_lengths) if sent_lengths else 0,
        "fragments_pct": round(fragments / len(sentences) * 100, 1) if sentences else 0,
        "long_sentences_pct": round(long_sents / len(sentences) * 100, 1) if sentences else 0,
        "avg_paragraph_length": round(statistics.mean(para_lengths), 1) if para_lengths else 0,
        "paragraph_length_std": round(statistics.stdev(para_lengths), 1) if len(para_lengths) > 1 else 0,
        "well_musical_pct": round(musical_count / total_well * 100, 1),
        "well_trade_pct": round(trade_count / total_well * 100, 1),
        "well_body_pct": round(body_count / total_well * 100, 1),
        "well_total_per_1k": round(well_hits / word_count * 1000, 1) if word_count > 0 else 0,
        "abstract_per_1k": round(abstract_count / word_count * 1000, 1) if word_count > 0 else 0,
        "dialogue_ratio": round(dialogue_ratio, 3),
        "em_dash_per_1k": round(em_per_1k, 1),
        "section_breaks": section_breaks,
        "he_start_pct": round(he_start_pct, 1),
        "the_way_count": the_way_count,
        "simile_density": round((like_count + as_count) / (word_count / 1000), 1) if word_count > 0 else 0,
    }

def main():
    results = {}
    wells = load_vocabulary_wells(BASE_DIR / "voice.md")
    for ch in chapter_numbers():
        path = CHAPTERS_DIR / f"ch_{ch:02d}.md"
        if path.exists():
            results[f"ch_{ch:02d}"] = analyze_chapter(path, wells=wells)
    
    # Compute novel-wide averages
    all_vals = list(results.values())
    avg = {}
    for key in all_vals[0]:
        vals = [r[key] for r in all_vals]
        avg[key] = round(statistics.mean(vals), 2)
    results["novel_average"] = avg
    
    # Find outliers (>1.5 std from mean)
    outliers = {}
    for key in all_vals[0]:
        vals = [r[key] for r in all_vals]
        if len(vals) > 2:
            m = statistics.mean(vals)
            s = statistics.stdev(vals)
            if s > 0:
                for ch_key, r in results.items():
                    if ch_key == "novel_average":
                        continue
                    z = (r[key] - m) / s
                    if abs(z) > 1.5:
                        if ch_key not in outliers:
                            outliers[ch_key] = []
                        direction = "HIGH" if z > 0 else "LOW"
                        outliers[ch_key].append(f"{key}: {r[key]} ({direction}, z={z:.1f})")
    
    # Print summary
    print("VOICE FINGERPRINT")
    print("=" * 70)
    print(f"{'Ch':<8} {'Words':<7} {'AvgSnt':<7} {'CV':<6} {'Frag%':<7} {'Long%':<7} {'Dial%':<7} {'Mus%':<6} {'Trd%':<6} {'Bod%':<6} {'AbsPK':<6} {'HeStrt':<7}")
    for key, r in results.items():
        if key == "novel_average":
            continue
        ch = int(key.split("_")[1])
        print(f"  {ch:<6} {r['word_count']:<7} {r['avg_sentence_length']:<7} {r['sentence_length_cv']:<6} {r['fragments_pct']:<7} {r['long_sentences_pct']:<7} {r['dialogue_ratio']:<7} {r['well_musical_pct']:<6} {r['well_trade_pct']:<6} {r['well_body_pct']:<6} {r['abstract_per_1k']:<6} {r['he_start_pct']:<7}")
    
    r = results["novel_average"]
    print(f"  {'AVG':<6} {r['word_count']:<7} {r['avg_sentence_length']:<7} {r['sentence_length_cv']:<6} {r['fragments_pct']:<7} {r['long_sentences_pct']:<7} {r['dialogue_ratio']:<7} {r['well_musical_pct']:<6} {r['well_trade_pct']:<6} {r['well_body_pct']:<6} {r['abstract_per_1k']:<6} {r['he_start_pct']:<7}")
    
    print(f"\n\nOUTLIERS (>1.5σ from mean):")
    for ch_key in sorted(outliers.keys()):
        print(f"  {ch_key}:")
        for o in outliers[ch_key]:
            print(f"    {o}")
    
    # Save full results
    out_path = BASE_DIR / "edit_logs" / "voice_fingerprint.json"
    with open(out_path, "w") as f:
        json.dump({"chapters": results, "outliers": outliers}, f, indent=2)
    print(f"\nSaved to {out_path}")

if __name__ == "__main__":
    main()
