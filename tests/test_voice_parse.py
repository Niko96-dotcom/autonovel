import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import gen_brief
import voice_fingerprint


class VoiceMdParseTests(unittest.TestCase):
    def test_extract_voice_rules_includes_part2_not_hardcoded_wells(self):
        md = (
            "# Voice Profile\n\n"
            "## Part 1: Guardrails\n"
            "- Max 1-2 em dashes per page\n\n"
            "## Part 2: Voice Identity (generated per novel)\n"
            "- River-glass diction: silt before metaphor; never name the freeze\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "voice.md"
            path.write_text(md)
            with patch.object(gen_brief, "VOICE_PATH", path):
                rules = gen_brief.extract_voice_rules()
        blob = "\n".join(rules)
        self.assertIn("River-glass diction: silt before metaphor", blob)
        self.assertNotIn("craft/trade/body", blob)
        self.assertNotIn("generic fantasy", blob.lower())

    def test_fingerprint_wells_ignore_bells_bronze_unless_voice_defines_them(self):
        md = (
            "## Part 1: Guardrails\n"
            "- No triadic sensory lists\n\n"
            "## Part 2: Voice Identity (generated per novel)\n"
            "### Vocabulary wells\n"
            "Musical: kelp, current\n"
            "Trade: net, salt\n"
            "Body: freeze\n"
        )
        chapter = (
            "The bronze bells rang and the clapper struck linseed into fugue. "
            "Kelp wrapped the current around her."
        )
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            (tmp_path / "voice.md").write_text(md)
            ch_path = tmp_path / "ch.md"
            ch_path.write_text(chapter)
            with patch.object(voice_fingerprint, "BASE_DIR", tmp_path):
                result = voice_fingerprint.analyze_chapter(ch_path)
        self.assertEqual(result["well_musical_pct"], 100.0)
        self.assertEqual(result["well_trade_pct"], 0.0)
        self.assertEqual(result["well_body_pct"], 0.0)
        # two musical hits (kelp, current); bells/bronze/clapper/linseed/fugue ignored
        self.assertGreater(result["well_total_per_1k"], 0.0)


if __name__ == "__main__":
    unittest.main()
