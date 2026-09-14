import unittest

from review import parse_review


class ReviewParsingTests(unittest.TestCase):
    def test_numeric_rating_and_professor_items_parse(self):
        review = """LITERARY CRITIC REVIEW
An uneven but promising novel. Rating: 4.5/5.

PROFESSOR OF FICTION REVIEW
1. Strengthen the midpoint
Severity: major
Suggestion: Move the discovery into chapter 8.

2. Trim the opening
Severity: minor
Suggestion: Cut the repeated description.
"""
        parsed = parse_review(review)
        self.assertEqual(parsed["stars"], 4.5)
        self.assertEqual(parsed["total_items"], 2)
        self.assertEqual(parsed["major_items"], 1)

    def test_symbol_rating_still_parses(self):
        parsed = parse_review("★★★★½\n\nProfessor Review\n1. Small issue\nMinor.")
        self.assertEqual(parsed["stars"], 4.5)


if __name__ == "__main__":
    unittest.main()
