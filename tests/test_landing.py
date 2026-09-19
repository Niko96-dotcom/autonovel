"""Regression tests for landing page CTA hrefs."""

import re
import unittest
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANDING = ROOT / "landing" / "index.html"


class _BtnAnchorParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = []

    def handle_starttag(self, tag, attrs):
        if tag != "a":
            return
        attr_map = dict(attrs)
        classes = attr_map.get("class", "").split()
        if "btn" in classes:
            self.hrefs.append(attr_map.get("href"))


def _is_allowed_href(href):
    if not href or href.startswith("about:"):
        return False
    if href.startswith(("http://", "https://")):
        return True
    # Relative file path: no scheme.
    return "://" not in href


class LandingCtaTests(unittest.TestCase):
    def test_btn_hrefs_are_real_and_about_empty_is_absent(self):
        html = LANDING.read_text(encoding="utf-8")
        self.assertNotIn("about:empty", html)
        self.assertIsNone(re.search(r'href\s*=\s*["\']about:empty["\']', html))

        parser = _BtnAnchorParser()
        parser.feed(html)
        self.assertTrue(parser.hrefs, "expected at least one remaining <a class=\"btn\">")
        for href in parser.hrefs:
            self.assertTrue(
                _is_allowed_href(href),
                f"btn href must be http(s) or a relative path, got {href!r}",
            )

    def test_cover_bg_png_exists_if_referenced(self):
        html = LANDING.read_text(encoding="utf-8")
        cover = ROOT / "landing" / "cover_bg.png"
        if "cover_bg.png" in html:
            self.assertTrue(
                cover.is_file(),
                "HTML references cover_bg.png but landing/cover_bg.png is missing",
            )
        else:
            self.assertNotIn("cover_bg.png", html)
