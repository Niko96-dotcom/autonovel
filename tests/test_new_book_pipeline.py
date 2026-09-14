import unittest
from pathlib import Path
from unittest.mock import patch

import book_config


class NewBookPipelineTests(unittest.TestCase):
    def test_structured_brief_controls_length(self):
        with patch(
            "book_config.load_book",
            return_value={"targetChapters": 18, "targetWords": 72_000},
        ):
            self.assertEqual(book_config.target_chapters(), 18)
            self.assertEqual(book_config.target_words(), 72_000)
            self.assertEqual(book_config.target_words_per_chapter(), 4_000)

    def test_active_text_pipeline_has_no_demo_book_prompt(self):
        root = Path(__file__).resolve().parent.parent
        active_files = [
            "gen_voice.py",
            "gen_world.py",
            "gen_characters.py",
            "gen_mystery.py",
            "gen_outline.py",
            "gen_canon.py",
            "draft_chapter.py",
            "gen_revision.py",
            "evaluate.py",
            "reader_panel.py",
            "build_arc_summary.py",
            "build_outline.py",
            "run_pipeline.py",
        ]
        forbidden = ["Cass Bellwright", "Cantamura", "Second Son of the House of Bells"]
        combined = "\n".join((root / name).read_text() for name in active_files)
        for demo_reference in forbidden:
            self.assertNotIn(demo_reference, combined)


if __name__ == "__main__":
    unittest.main()
