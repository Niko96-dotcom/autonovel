import unittest
from pathlib import Path


class LLMRoutingTests(unittest.TestCase):
    def test_only_shared_client_contains_provider_endpoints(self):
        root = Path(__file__).parents[1]
        offenders = []
        for path in root.glob("*.py"):
            if path.name == "llm_client.py":
                continue
            text = path.read_text()
            if "/v1/messages" in text or "/v1/chat/completions" in text:
                offenders.append(path.name)
        self.assertEqual(offenders, [])


if __name__ == "__main__":
    unittest.main()
