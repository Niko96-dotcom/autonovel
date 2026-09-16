import os
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

import llm_client


class LLMClientTests(unittest.TestCase):
    @patch.dict(
        os.environ,
        {
            "AUTONOVEL_LLM_PROVIDER": "openai",
            "AUTONOVEL_API_BASE_URL": "http://127.0.0.1:8081/v1",
            "AUTONOVEL_API_KEY": "local-test-key",
            "AUTONOVEL_CONTEXT_SIZE": "32768",
        },
        clear=True,
    )
    @patch("llm_client.httpx.post")
    def test_openai_compatible_request(self, post):
        response = MagicMock()
        response.json.return_value = {
            "choices": [{"message": {"content": "local reply"}}]
        }
        post.return_value = response

        result = llm_client.call_llm(
            "hello",
            model="gemstrike-31b",
            system="write well",
            max_tokens=50,
            temperature=0.7,
        )

        self.assertEqual(result, "local reply")
        url = post.call_args.args[0]
        kwargs = post.call_args.kwargs
        self.assertEqual(url, "http://127.0.0.1:8081/v1/chat/completions")
        self.assertEqual(kwargs["headers"]["Authorization"], "Bearer local-test-key")
        self.assertEqual(kwargs["json"]["messages"][0], {"role": "system", "content": "write well"})
        self.assertEqual(kwargs["json"]["messages"][1], {"role": "user", "content": "hello"})

    @patch.dict(
        os.environ,
        {
            "AUTONOVEL_LLM_PROVIDER": "anthropic",
            "AUTONOVEL_API_BASE_URL": "https://api.anthropic.com",
            "ANTHROPIC_API_KEY": "anthropic-test-key",
        },
        clear=True,
    )
    @patch("llm_client.httpx.post")
    def test_anthropic_request_remains_supported(self, post):
        response = MagicMock()
        response.json.return_value = {
            "content": [{"type": "text", "text": "anthropic reply"}]
        }
        post.return_value = response

        result = llm_client.call_llm("hello", model="claude-test", system="judge")

        self.assertEqual(result, "anthropic reply")
        self.assertEqual(post.call_args.args[0], "https://api.anthropic.com/v1/messages")
        self.assertEqual(post.call_args.kwargs["headers"]["x-api-key"], "anthropic-test-key")
        self.assertEqual(post.call_args.kwargs["json"]["system"], "judge")

    def test_api_key_file_is_supported(self):
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            key_path = Path(tmp) / "key"
            key_path.write_text("file-key\n")
            env = {
                "AUTONOVEL_LLM_PROVIDER": "openai",
                "AUTONOVEL_API_BASE_URL": "http://localhost:8081",
                "AUTONOVEL_API_KEY_FILE": str(key_path),
            }
            with patch.dict(os.environ, env, clear=True):
                self.assertIsNone(llm_client.configuration_error())

    @patch.dict(
        os.environ,
        {
            "AUTONOVEL_LLM_PROVIDER": "openai",
            "AUTONOVEL_API_BASE_URL": "http://localhost:11434",
        },
        clear=True,
    )
    @patch("llm_client.httpx.post")
    def test_local_openai_backend_can_run_without_api_key(self, post):
        response = MagicMock()
        response.json.return_value = {
            "choices": [{"message": {"content": "local reply"}}]
        }
        post.return_value = response

        result = llm_client.call_llm("hello", model="local-model")

        self.assertEqual(result, "local reply")
        self.assertNotIn("Authorization", post.call_args.kwargs["headers"])

    @patch.dict(
        os.environ,
        {
            "AUTONOVEL_LLM_PROVIDER": "openai",
            "AUTONOVEL_API_BASE_URL": "https://models.example.org/v1",
        },
        clear=True,
    )
    def test_remote_openai_backend_still_requires_api_key(self):
        self.assertIn("No LLM API key configured", llm_client.configuration_error())

    @patch.dict(
        os.environ,
        {
            "AUTONOVEL_LLM_PROVIDER": "openai",
            "AUTONOVEL_API_BASE_URL": "https://models.example.org/v1",
            "AUTONOVEL_API_KEY_FILE": "keychain:org.nousresearch.autonovelstudio",
            "AUTONOVEL_API_KEY": "from-env",
        },
        clear=True,
    )
    def test_keychain_sentinel_falls_through_to_api_key(self):
        self.assertIsNone(llm_client.configuration_error())
        self.assertEqual(llm_client._api_key(), "from-env")

    @patch.dict(
        os.environ,
        {
            "AUTONOVEL_LLM_PROVIDER": "openai",
            "AUTONOVEL_API_BASE_URL": "https://models.example.org/v1",
            "AUTONOVEL_API_KEY_FILE": "keychain:org.nousresearch.autonovelstudio",
        },
        clear=True,
    )
    def test_keychain_sentinel_without_key_is_not_a_file_read(self):
        self.assertIn("No LLM API key configured", llm_client.configuration_error())

    @patch.dict(
        os.environ,
        {
            "AUTONOVEL_LLM_PROVIDER": "openai",
            "AUTONOVEL_API_BASE_URL": "http://localhost:8081",
            "AUTONOVEL_API_KEY": "key",
            "AUTONOVEL_CONTEXT_SIZE": "1024",
        },
        clear=True,
    )
    def test_impossible_prompt_fails_before_http(self):
        with self.assertRaises(llm_client.LLMConfigurationError):
            llm_client.call_llm("x" * 10_000, model="local")


if __name__ == "__main__":
    unittest.main()
