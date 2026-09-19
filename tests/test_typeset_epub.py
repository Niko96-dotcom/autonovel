"""EPUB typeset files must ship real identity, not placeholders."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TYPESET = ROOT / "typeset"
NOVEL_TEX = TYPESET / "novel.tex"
METADATA = TYPESET / "epub_metadata.yaml"
FRONT_MATTER = TYPESET / "epub_front_matter.md"
COLOPHON = TYPESET / "epub_colophon.md"
BACK_COVER = TYPESET / "epub_back_cover.md"
CANONICAL_URL = "https://nousresearch.com/bells"
PLACEHOLDERS = (
    "NOVEL TITLE",
    "Author Name",
    "example.com",
    "epub_back_cover.png",
)


def _hypersetup_field(tex: str, key: str) -> str:
    match = re.search(rf"{re.escape(key)}\={{([^}}]+)}}", tex)
    if not match:
        raise AssertionError(f"missing {key} in novel.tex")
    return match.group(1)


class TypesetEpubIdentityTests(unittest.TestCase):
    def test_epub_metadata_has_no_placeholders_and_matches_novel_tex(self):
        meta = METADATA.read_text(encoding="utf-8")
        tex = NOVEL_TEX.read_text(encoding="utf-8")
        title = _hypersetup_field(tex, "pdftitle")
        author = _hypersetup_field(tex, "pdfauthor")

        self.assertNotIn("title: TITLE", meta)
        self.assertNotIn("author: AUTHOR", meta)
        self.assertNotIn("publisher: Publisher Name", meta)
        self.assertRegex(meta, re.compile(rf"^title:\s*{re.escape(title)}\s*$", re.M))
        self.assertRegex(meta, re.compile(rf"^author:\s*{re.escape(author)}\s*$", re.M))

        cover = re.search(r"^cover-image:\s*(.+)\s*$", meta, re.M)
        if cover is not None:
            self.assertEqual(cover.group(1).strip(), "../art/cover.png")

    def test_front_matter_colophon_and_back_cover_have_identity_not_placeholders(self):
        tex = NOVEL_TEX.read_text(encoding="utf-8")
        title = _hypersetup_field(tex, "pdftitle")
        author = _hypersetup_field(tex, "pdfauthor")
        front = FRONT_MATTER.read_text(encoding="utf-8")
        colophon = COLOPHON.read_text(encoding="utf-8")
        back = BACK_COVER.read_text(encoding="utf-8")

        for blob in (front, colophon, back):
            for placeholder in PLACEHOLDERS:
                self.assertNotIn(placeholder, blob)

        self.assertNotIn("![", back)
        self.assertNotIn("epub_back_cover.png", back)
        self.assertIsNone(re.search(r"!\[[^\]]*\]\([^)]*\)", back))

        self.assertIn(title, front)
        self.assertIn(author, front)
        self.assertIn("Created by Hermes Agent", front)
        self.assertIn(CANONICAL_URL, front)
        self.assertIn(CANONICAL_URL, colophon)
        self.assertIn(CANONICAL_URL, tex)


if __name__ == "__main__":
    unittest.main()
