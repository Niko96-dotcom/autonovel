import argparse
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

import book_config

# Bare `python3 -m unittest` does not install project deps.
sys.modules.setdefault("dotenv", MagicMock())
_llm_stub = sys.modules.setdefault("llm_client", MagicMock())
if isinstance(_llm_stub, MagicMock):
    _llm_stub.pipeline_timeouts.return_value = (600, 1800)

import reader_panel
import run_pipeline


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

    def test_discard_stale_arc_summary_removes_prior_book(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            leftover = tmp_path / "arc_summary.md"
            leftover.write_text("previous book")
            with patch.object(run_pipeline, "BASE_DIR", tmp_path):
                run_pipeline.discard_stale_arc_summary()
            self.assertFalse(leftover.exists())

    def test_from_scratch_discards_prior_arc_summary(self):
        args = argparse.Namespace(from_scratch=True, phase="foundation", max_cycles=None)
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            (tmp_path / "seed.txt").write_text("seed")
            leftover = tmp_path / "arc_summary.md"
            leftover.write_text("previous book")
            state = run_pipeline.default_state()
            with patch.object(run_pipeline, "BASE_DIR", tmp_path), patch.object(
                run_pipeline, "STATE_FILE", tmp_path / "state.json"
            ), patch.object(run_pipeline, "run_foundation", return_value=state), patch.object(
                run_pipeline, "count_words_in_chapters", return_value=0
            ):
                run_pipeline.run_pipeline(args)
            self.assertFalse(leftover.exists())

    def test_reader_panel_does_not_start_without_arc_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(reader_panel, "BASE_DIR", Path(tmp)):
                with self.assertRaises(SystemExit) as ctx:
                    reader_panel.main()
            self.assertNotEqual(ctx.exception.code, 0)

    def test_missing_panel_json_is_not_empty_consensus(self):
        with tempfile.TemporaryDirectory() as tmp:
            missing = Path(tmp) / "reader_panel.json"
            with self.assertRaises(RuntimeError):
                run_pipeline.parse_panel_consensus(missing)

    def test_run_revision_builds_arc_summary_before_reader_panel(self):
        calls = []

        def fake_generation(script, timeout):
            calls.append(script)
            if script == "reader_panel.py":
                panel_path = run_pipeline.EDIT_LOGS_DIR / "reader_panel.json"
                panel_path.write_text(json.dumps({"readers": {}, "disagreements": []}))

        def fake_uv_run(script, timeout=600):
            return subprocess.CompletedProcess(
                script, 0, stdout="novel_score: 8.0\noverall_score: 8.0\n", stderr=""
            )

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            state = run_pipeline.default_state()
            with patch.object(run_pipeline, "run_generation", side_effect=fake_generation), patch.object(
                run_pipeline, "uv_run", side_effect=fake_uv_run
            ), patch.object(run_pipeline, "BASE_DIR", tmp_path), patch.object(
                run_pipeline, "EDIT_LOGS_DIR", tmp_path
            ), patch.object(run_pipeline, "BRIEFS_DIR", tmp_path), patch.object(
                run_pipeline, "save_state"
            ), patch.object(run_pipeline, "git_add_commit", return_value="abc"), patch.object(
                run_pipeline, "log_result"
            ), patch.object(run_pipeline, "count_words_in_chapters", return_value=0):
                run_pipeline.run_revision(state, max_cycles=1)

        self.assertIn("build_arc_summary.py", calls)
        self.assertIn("reader_panel.py", calls)
        self.assertLess(
            calls.index("build_arc_summary.py"), calls.index("reader_panel.py")
        )

    def test_failed_panel_does_not_continue_as_empty_consensus(self):
        def fake_generation(script, timeout):
            if script == "reader_panel.py":
                raise RuntimeError("reader_panel.py failed: boom")

        def fake_uv_run(script, timeout=600):
            return subprocess.CompletedProcess(script, 0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            state = run_pipeline.default_state()
            with patch.object(run_pipeline, "run_generation", side_effect=fake_generation), patch.object(
                run_pipeline, "uv_run", side_effect=fake_uv_run
            ), patch.object(run_pipeline, "BASE_DIR", tmp_path), patch.object(
                run_pipeline, "EDIT_LOGS_DIR", tmp_path
            ), patch.object(run_pipeline, "BRIEFS_DIR", tmp_path), patch.object(
                run_pipeline, "save_state"
            ), patch.object(run_pipeline, "git_add_commit", return_value="abc"), patch.object(
                run_pipeline, "log_result"
            ), patch.object(run_pipeline, "count_words_in_chapters", return_value=0):
                with self.assertRaises(RuntimeError) as ctx:
                    run_pipeline.run_revision(state, max_cycles=1)
        self.assertIn("reader_panel.py", str(ctx.exception))

    def test_git_add_commit_stages_novel_artifacts_not_all(self):
        cmds = []

        def fake_run_tool(cmd, timeout=600, check=False):
            cmds.append(cmd)
            return subprocess.CompletedProcess(cmd, 0, stdout="abc123\n", stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            (tmp_path / "chapters").mkdir()
            (tmp_path / "voice.md").write_text("voice")
            (tmp_path / "unrelated.py").write_text("leave me unstaged")
            with patch.object(run_pipeline, "run_tool", side_effect=fake_run_tool), patch.object(
                run_pipeline, "BASE_DIR", tmp_path
            ):
                run_pipeline.git_add_commit("revision keep")

        add_cmds = [cmd for cmd in cmds if cmd.startswith("git add")]
        self.assertEqual(len(add_cmds), 1)
        self.assertNotIn("git add -A", add_cmds[0])
        self.assertIn("voice.md", add_cmds[0])
        self.assertIn("chapters", add_cmds[0])
        self.assertNotIn("unrelated.py", add_cmds[0])

    def test_worse_revision_restores_only_that_chapter(self):
        tool_cmds = []

        def fake_generation(script, timeout):
            if script == "reader_panel.py":
                panel_path = run_pipeline.EDIT_LOGS_DIR / "reader_panel.json"
                panel_path.write_text(json.dumps({
                    "readers": {},
                    "disagreements": [{
                        "chapter": 2,
                        "question": "cut_candidate",
                        "flagged_by": ["r1", "r2", "r3"],
                    }],
                }))

        chapter_evals = iter(["overall_score: 8.0\n", "overall_score: 5.0\n"])

        def fake_uv_run(script, timeout=600):
            if "evaluate.py --chapter" in script:
                stdout = next(chapter_evals)
            else:
                stdout = "novel_score: 8.0\noverall_score: 8.0\n"
            return subprocess.CompletedProcess(script, 0, stdout=stdout, stderr="")

        def fake_run_tool(cmd, timeout=600, check=False):
            tool_cmds.append(cmd)
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            chapters = tmp_path / "chapters"
            chapters.mkdir()
            (chapters / "ch_01.md").write_text("apply_cuts still here")
            (chapters / "ch_02.md").write_text("worse revision")
            state = run_pipeline.default_state()
            with patch.object(run_pipeline, "run_generation", side_effect=fake_generation), patch.object(
                run_pipeline, "uv_run", side_effect=fake_uv_run
            ), patch.object(run_pipeline, "run_tool", side_effect=fake_run_tool), patch.object(
                run_pipeline, "BASE_DIR", tmp_path
            ), patch.object(run_pipeline, "EDIT_LOGS_DIR", tmp_path), patch.object(
                run_pipeline, "BRIEFS_DIR", tmp_path
            ), patch.object(run_pipeline, "CHAPTERS_DIR", chapters), patch.object(
                run_pipeline, "save_state"
            ), patch.object(run_pipeline, "log_result"), patch.object(
                run_pipeline, "count_words_in_chapters", return_value=0
            ):
                run_pipeline.run_revision(state, max_cycles=1)

        self.assertTrue(any("git checkout -- chapters/ch_02.md" in cmd for cmd in tool_cmds))
        self.assertFalse(any("git checkout -- chapters/ch_01.md" in cmd for cmd in tool_cmds))
        self.assertFalse(any("git reset --hard" in cmd for cmd in tool_cmds))
        self.assertFalse(any("git add -A" in cmd for cmd in tool_cmds))

    def test_run_revision_stops_review_loop_when_few_items(self):
        uv_scripts = []
        tool_cmds = []

        def fake_generation(script, timeout):
            if script == "reader_panel.py":
                panel_path = run_pipeline.EDIT_LOGS_DIR / "reader_panel.json"
                panel_path.write_text(json.dumps({"readers": {}, "disagreements": []}))

        def fake_uv_run(script, timeout=600):
            uv_scripts.append(script)
            return subprocess.CompletedProcess(
                script, 0, stdout="novel_score: 8.0\noverall_score: 8.0\n", stderr=""
            )

        def fake_run_tool(cmd, timeout=600, check=False):
            tool_cmds.append(cmd)
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            (tmp_path / "review.py").write_text("")
            (tmp_path / "20260101_review.json").write_text(json.dumps({
                "stars": 3.0,
                "total_items": 2,
                "major_items": 2,
                "qualified_items": 0,
            }))
            state = run_pipeline.default_state()
            with patch.object(run_pipeline, "run_generation", side_effect=fake_generation), patch.object(
                run_pipeline, "uv_run", side_effect=fake_uv_run
            ), patch.object(run_pipeline, "run_tool", side_effect=fake_run_tool), patch.object(
                run_pipeline, "BASE_DIR", tmp_path
            ), patch.object(run_pipeline, "EDIT_LOGS_DIR", tmp_path), patch.object(
                run_pipeline, "BRIEFS_DIR", tmp_path
            ), patch.object(run_pipeline, "save_state"), patch.object(
                run_pipeline, "git_add_commit", return_value="abc"
            ), patch.object(run_pipeline, "log_result"), patch.object(
                run_pipeline, "count_words_in_chapters", return_value=0
            ):
                run_pipeline.run_revision(state, max_cycles=1)

        self.assertEqual(len([s for s in uv_scripts if "review.py" in s]), 1)
        self.assertFalse(any("gen_brief.py --auto" in cmd for cmd in tool_cmds))


if __name__ == "__main__":
    unittest.main()
