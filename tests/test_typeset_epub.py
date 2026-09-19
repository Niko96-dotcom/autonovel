"""EPUB/typeset identity must follow book.json, not a frozen sample title."""

import importlib.util
import json
import re
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
TYPESET = ROOT / "typeset"
PLACEHOLDERS = (
    "NOVEL TITLE",
    "Author Name",
    "example.com",
    "TITLE",
    "AUTHOR",
    "Publisher Name",
    "epub_back_cover.png",
)


def _load_build_tex():
    spec = importlib.util.spec_from_file_location(
        "build_tex",
        TYPESET / "build_tex.py",
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _hypersetup_field(tex: str, key: str) -> str:
    match = re.search(rf"{re.escape(key)}\={{([^}}]+)}}", tex)
    if not match:
        raise AssertionError(f"missing {key} in novel.tex")
    return match.group(1)


class TypesetEpubIdentityTests(unittest.TestCase):
    def test_build_tex_substitutes_book_json_into_novel_and_epub(self):
        build_tex = _load_build_tex()
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            chapters = tmp_path / "chapters"
            typeset_dir = tmp_path / "typeset"
            chapters.mkdir()
            typeset_dir.mkdir()
            (chapters / "ch_01.md").write_text(
                "# Chapter 1: Opening\n\nFirst scene.\n"
            )
            (tmp_path / "book.json").write_text(
                json.dumps(
                    {
                        "title": "River Glass",
                        "author": "Ada Vale",
                        "genre": "Mystery",
                        "publisher": "Glass Press",
                        "url": "https://books.example/river-glass",
                    }
                )
            )
            # Bells-only strings must not remain after substitution.
            (typeset_dir / "novel.tex").write_text(
                "pdftitle={The Second Son of the House of Bells}\n"
            )
            with patch.object(build_tex, "BASE_DIR", tmp_path), patch.object(
                build_tex, "CHAPTERS_DIR", chapters
            ), patch.object(build_tex, "OUT_DIR", typeset_dir):
                build_tex.main()

            tex = (typeset_dir / "novel.tex").read_text(encoding="utf-8")
            meta = (typeset_dir / "epub_metadata.yaml").read_text(encoding="utf-8")
            front = (typeset_dir / "epub_front_matter.md").read_text(
                encoding="utf-8"
            )
            colophon = (typeset_dir / "epub_colophon.md").read_text(
                encoding="utf-8"
            )
            back = (typeset_dir / "epub_back_cover.md").read_text(encoding="utf-8")

            self.assertEqual(_hypersetup_field(tex, "pdftitle"), "River Glass")
            self.assertEqual(_hypersetup_field(tex, "pdfauthor"), "Ada Vale")
            self.assertIn("Mystery Novel", tex)
            self.assertIn("River Glass", tex)
            self.assertIn("Ada Vale", tex)
            self.assertNotIn("House of Bells", tex)
            self.assertNotIn("Claude Hermes", tex)

            self.assertRegex(
                meta, re.compile(r"^title:\s*River Glass\s*$", re.M)
            )
            self.assertRegex(
                meta, re.compile(r"^author:\s*Ada Vale\s*$", re.M)
            )
            self.assertRegex(
                meta, re.compile(r"^publisher:\s*Glass Press\s*$", re.M)
            )
            self.assertIn("River Glass", front)
            self.assertIn("Ada Vale", front)
            self.assertIn("https://books.example/river-glass", front)
            self.assertIn("https://books.example/river-glass", colophon)
            self.assertNotIn("House of Bells", front)
            self.assertNotIn("nousresearch.com/bells", colophon)
            self.assertNotIn("![", back)
            self.assertNotIn("epub_back_cover.png", back)

    def test_bells_fixture_book_json_still_substitutes(self):
        """Bells identity is fine as a fixture book.json, not a hardcoded path."""
        build_tex = _load_build_tex()
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            chapters = tmp_path / "chapters"
            typeset_dir = tmp_path / "typeset"
            chapters.mkdir()
            typeset_dir.mkdir()
            (chapters / "ch_01.md").write_text("# Chapter 1: Test\n\nBody.\n")
            (tmp_path / "book.json").write_text(
                json.dumps(
                    {
                        "title": "The Second Son of the House of Bells",
                        "author": "Claude Hermes",
                        "genre": "Fantasy",
                        "publisher": "Nous Research",
                        "url": "https://nousresearch.com/bells",
                    }
                )
            )
            with patch.object(build_tex, "BASE_DIR", tmp_path), patch.object(
                build_tex, "CHAPTERS_DIR", chapters
            ), patch.object(build_tex, "OUT_DIR", typeset_dir):
                build_tex.main()

            tex = (typeset_dir / "novel.tex").read_text(encoding="utf-8")
            meta = (typeset_dir / "epub_metadata.yaml").read_text(encoding="utf-8")
            self.assertEqual(
                _hypersetup_field(tex, "pdftitle"),
                "The Second Son of the House of Bells",
            )
            self.assertIn("title: The Second Son of the House of Bells", meta)

    def test_committed_epub_templates_are_placeholders_not_bells_freeze(self):
        meta = (TYPESET / "epub_metadata.yaml").read_text(encoding="utf-8")
        front = (TYPESET / "epub_front_matter.md").read_text(encoding="utf-8")
        self.assertIn("title: TITLE", meta)
        self.assertIn("author: AUTHOR", meta)
        self.assertIn("NOVEL TITLE", front)
        self.assertIn("Author Name", front)
        self.assertNotIn("House of Bells", meta)
        self.assertNotIn("House of Bells", front)
        for name in PLACEHOLDERS[:3]:
            self.assertTrue(name)


if __name__ == "__main__":
    unittest.main()
