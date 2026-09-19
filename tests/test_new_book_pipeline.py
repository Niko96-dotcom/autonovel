import argparse
import importlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

import book_config

# Bare `python3 -m unittest` does not install project deps.
sys.modules.setdefault("dotenv", MagicMock())
sys.modules.setdefault("PIL", MagicMock())
sys.modules.setdefault("PIL.Image", MagicMock())
sys.modules.setdefault("PIL.ImageDraw", MagicMock())
sys.modules.setdefault("PIL.ImageFont", MagicMock())
sys.modules.setdefault("PIL.ImageFilter", MagicMock())
if "llm_client" not in sys.modules:
    try:
        import llm_client as _llm_client  # noqa: F401
    except ImportError:
        _llm_stub = MagicMock()
        _llm_stub.pipeline_timeouts.return_value = (600, 1800)
        sys.modules["llm_client"] = _llm_stub

import adversarial_edit
import apply_cuts
import compare_chapters
import draft_chapter
import gen_art_directions
import gen_revision
import gen_audiobook
import gen_audiobook_script
import gen_cover_composite
import gen_cover_print
import reader_panel
import run_drafts
import run_pipeline
import voice_fingerprint


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
            "gen_audiobook_script.py",
            "gen_cover_print.py",
            "gen_cover_composite.py",
            "gen_art_directions.py",
        ]
        forbidden = ["Cass Bellwright", "Cantamura", "Second Son of the House of Bells"]
        combined = "\n".join((root / name).read_text() for name in active_files)
        for demo_reference in forbidden:
            self.assertNotIn(demo_reference, combined)

    def test_art_tools_use_book_config_not_demo_book(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            with patch.object(book_config, "BASE_DIR", tmp_path), patch.object(
                gen_cover_print, "compose_cover"
            ) as print_cover, patch.object(sys, "argv", ["gen_cover_print.py", "art.png"]):
                gen_cover_print.main()
            self.assertEqual(print_cover.call_args.args[1], "Untitled Novel")
            self.assertNotIn("Second Son of the House of Bells", print_cover.call_args.args[1])

            with patch.object(book_config, "BASE_DIR", tmp_path), patch.object(
                gen_cover_composite, "composite_cover"
            ) as ebook_cover, patch.object(
                sys, "argv", ["gen_cover_composite.py", "art.png"]
            ):
                gen_cover_composite.main()
            self.assertEqual(ebook_cover.call_args.args[1], "Untitled Novel")
            self.assertNotIn("Second Son of the House of Bells", ebook_cover.call_args.args[1])

            (tmp_path / "book.json").write_text(
                json.dumps({"title": "River Glass", "author": "Ada Vale"})
            )
            with patch.object(book_config, "BASE_DIR", tmp_path), patch.object(
                gen_cover_print, "compose_cover"
            ) as print_cover, patch.object(sys, "argv", ["gen_cover_print.py", "art.png"]):
                gen_cover_print.main()
            self.assertEqual(print_cover.call_args.args[1], "River Glass")
            self.assertEqual(print_cover.call_args.args[2], "Ada Vale")

            with patch.object(book_config, "BASE_DIR", tmp_path), patch.object(
                gen_cover_composite, "composite_cover"
            ) as ebook_cover, patch.object(
                sys, "argv", ["gen_cover_composite.py", "art.png"]
            ):
                gen_cover_composite.main()
            self.assertEqual(ebook_cover.call_args.args[1], "River Glass")
            self.assertEqual(ebook_cover.call_args.args[2], "Ada Vale")

        captured = {}

        def fake_call_model(prompt, max_tokens=3000):
            captured["prompt"] = prompt
            return json.dumps([
                {"direction": "abstract", "concept": "c", "medium": "ink", "prompt": "p"}
            ])

        with patch.object(gen_art_directions, "call_model", side_effect=fake_call_model):
            gen_art_directions.generate_directions("cover", {}, n=1)
        prompt = captured["prompt"].lower()
        for phrase in ("bronze bell", "pitch-gauge", "limestone bowl city"):
            self.assertNotIn(phrase, prompt)

    def test_discard_stale_arc_summary_removes_prior_book(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            leftover = tmp_path / "arc_summary.md"
            leftover.write_text("previous book")
            with patch.object(run_pipeline, "BASE_DIR", tmp_path):
                run_pipeline.discard_stale_arc_summary()
            self.assertFalse(leftover.exists())

    def test_discard_stale_chapters_removes_prior_book(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            leftover = tmp_path / "ch_19.md"
            leftover.write_text("previous book")
            stray = tmp_path / "notes.md"
            stray.write_text("keep")
            with patch.object(run_pipeline, "CHAPTERS_DIR", tmp_path):
                run_pipeline.discard_stale_chapters()
            self.assertFalse(leftover.exists())
            self.assertTrue(stray.exists())

    def test_from_scratch_discards_prior_arc_summary(self):
        args = argparse.Namespace(from_scratch=True, phase="foundation", max_cycles=None)
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            (tmp_path / "seed.txt").write_text("seed")
            leftover = tmp_path / "arc_summary.md"
            leftover.write_text("previous book")
            chapters = tmp_path / "chapters"
            chapters.mkdir()
            leftover_chapter = chapters / "ch_19.md"
            leftover_chapter.write_text("previous book chapter")
            stray = chapters / "notes.md"
            stray.write_text("keep")
            state = run_pipeline.default_state()
            with patch.object(run_pipeline, "BASE_DIR", tmp_path), patch.object(
                run_pipeline, "STATE_FILE", tmp_path / "state.json"
            ), patch.object(run_pipeline, "CHAPTERS_DIR", chapters), patch.object(
                run_pipeline, "run_foundation", return_value=state
            ), patch.object(
                run_pipeline, "count_words_in_chapters", return_value=0
            ):
                run_pipeline.run_pipeline(args)
            self.assertFalse(leftover.exists())
            self.assertFalse(leftover_chapter.exists())
            self.assertTrue(stray.exists())

    def test_resume_without_from_scratch_keeps_chapters(self):
        args = argparse.Namespace(from_scratch=False, phase="foundation", max_cycles=None)
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            chapters = tmp_path / "chapters"
            chapters.mkdir()
            leftover_chapter = chapters / "ch_19.md"
            leftover_chapter.write_text("previous book chapter")
            state = run_pipeline.default_state()
            with patch.object(run_pipeline, "BASE_DIR", tmp_path), patch.object(
                run_pipeline, "STATE_FILE", tmp_path / "state.json"
            ), patch.object(run_pipeline, "CHAPTERS_DIR", chapters), patch.object(
                run_pipeline, "load_state", return_value=state
            ), patch.object(
                run_pipeline, "run_foundation", return_value=state
            ), patch.object(
                run_pipeline, "count_words_in_chapters", return_value=0
            ):
                run_pipeline.run_pipeline(args)
            self.assertTrue(leftover_chapter.exists())

    def test_reader_panel_does_not_start_without_arc_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(reader_panel, "BASE_DIR", Path(tmp)):
                with self.assertRaises(SystemExit) as ctx:
                    reader_panel.main()
            self.assertNotEqual(ctx.exception.code, 0)

    def test_all_failed_readers_exit_nonzero_without_empty_panel(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            (tmp_path / "arc_summary.md").write_text("summary")
            with patch.object(reader_panel, "BASE_DIR", tmp_path), patch.object(
                reader_panel, "call_reader", side_effect=RuntimeError("llm down")
            ):
                with self.assertRaises(SystemExit) as ctx:
                    reader_panel.main()
            self.assertNotEqual(ctx.exception.code, 0)
            self.assertFalse((tmp_path / "edit_logs" / "reader_panel.json").exists())

    def test_missing_panel_json_is_not_empty_consensus(self):
        with tempfile.TemporaryDirectory() as tmp:
            missing = Path(tmp) / "reader_panel.json"
            with self.assertRaises(RuntimeError):
                run_pipeline.parse_panel_consensus(missing)

    def test_panel_chapter_mentions_use_word_boundary_helper(self):
        self.assertEqual(
            book_config.extract_mentioned_chapters("which 2 scenes later"), []
        )
        self.assertEqual(
            book_config.extract_mentioned_chapters("such 5 details"), []
        )
        self.assertEqual(book_config.extract_mentioned_chapters("Chapter 3"), [3])
        self.assertEqual(book_config.extract_mentioned_chapters("Ch 4"), [4])
        self.assertEqual(book_config.extract_mentioned_chapters("Chapter 12"), [12])
        self.assertIs(
            reader_panel.extract_mentioned_chapters,
            book_config.extract_mentioned_chapters,
        )
        self.assertIs(
            run_pipeline.extract_mentioned_chapters,
            book_config.extract_mentioned_chapters,
        )

        disagreements = reader_panel.find_disagreements({
            "editor": {
                "momentum_loss": "which 2 scenes later the pacing dips",
                "cut_candidate": "",
                "thinnest_character": "",
                "worst_scene": "Chapter 12 is the weakest scene",
            },
            "genre_reader": {
                "momentum_loss": "such 5 details pile up",
                "cut_candidate": "",
                "thinnest_character": "",
                "worst_scene": "Chapter 3 and Ch 4 also stall",
            },
        })
        self.assertEqual({d["chapter"] for d in disagreements}, {3, 4, 12})

        with tempfile.TemporaryDirectory() as tmp:
            panel = Path(tmp) / "panel.json"
            panel.write_text(json.dumps({
                "disagreements": [],
                "readers": {
                    "editor": {
                        "momentum_loss": "which 2 scenes later Chapter 3 stalls",
                        "cut_candidate": "such 5 details",
                        "worst_scene": "Ch 4",
                        "thinnest_character": "",
                        "missing_scene": "Chapter 12",
                    },
                },
            }))
            self.assertEqual(
                {item["chapter"] for item in run_pipeline.parse_panel_consensus(panel)},
                {3, 4, 12},
            )

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

    def test_worse_foundation_restores_only_planning_docs(self):
        tool_cmds = []
        planning = (
            "voice.md",
            "world.md",
            "characters.md",
            "outline.md",
            "canon.md",
            "MYSTERY.md",
        )

        def fake_uv_run(script, timeout=600):
            return subprocess.CompletedProcess(
                script, 0, stdout="overall_score: 5.0\nlore_score: 4.0\n", stderr=""
            )

        def fake_run_tool(cmd, timeout=600, check=False):
            tool_cmds.append(cmd)
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            chapters = tmp_path / "chapters"
            chapters.mkdir()
            chapter_path = chapters / "ch_01.md"
            chapter_path.write_text("keep this chapter")
            pipeline_src = tmp_path / "run_pipeline.py"
            pipeline_src.write_text("pipeline source")
            (tmp_path / "state.json").write_text("{}")
            (tmp_path / "results.tsv").write_text("tsv")
            for name in planning:
                (tmp_path / name).write_text("new planning")
            state = run_pipeline.default_state()
            state["foundation_score"] = 8.0
            with patch.object(run_pipeline, "run_generation"), patch.object(
                run_pipeline, "uv_run", side_effect=fake_uv_run
            ), patch.object(run_pipeline, "run_tool", side_effect=fake_run_tool), patch.object(
                run_pipeline, "BASE_DIR", tmp_path
            ), patch.object(run_pipeline, "CHAPTERS_DIR", chapters), patch.object(
                run_pipeline, "save_state"
            ), patch.object(run_pipeline, "log_result"):
                run_pipeline.run_foundation(state)

            self.assertEqual(chapter_path.read_text(), "keep this chapter")
            self.assertEqual(pipeline_src.read_text(), "pipeline source")

        checkout_cmds = [cmd for cmd in tool_cmds if "git checkout --" in cmd]
        checkout_blob = " ".join(checkout_cmds)
        for name in planning:
            self.assertIn(name, checkout_blob)
        self.assertFalse(any("git reset --hard" in cmd for cmd in tool_cmds))
        self.assertFalse(any("git add -A" in cmd for cmd in tool_cmds))
        self.assertNotIn("state.json", checkout_blob)
        self.assertNotIn("results.tsv", checkout_blob)
        self.assertFalse(any("chapters/" in cmd for cmd in checkout_cmds))
        self.assertFalse(any("run_pipeline.py" in cmd for cmd in checkout_cmds))

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

    def test_foundation_eval_timeout_does_not_checkout_planning_docs(self):
        tool_cmds = []
        planning = (
            "voice.md",
            "world.md",
            "characters.md",
            "outline.md",
            "canon.md",
            "MYSTERY.md",
        )

        def fake_uv_run(script, timeout=600):
            return subprocess.CompletedProcess(
                script, -1, stdout="", stderr="TIMEOUT"
            )

        def fake_run_tool(cmd, timeout=600, check=False):
            tool_cmds.append(cmd)
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            for name in planning:
                (tmp_path / name).write_text("new planning")
            state = run_pipeline.default_state()
            state["foundation_score"] = 8.0
            with patch.object(run_pipeline, "run_generation"), patch.object(
                run_pipeline, "uv_run", side_effect=fake_uv_run
            ), patch.object(run_pipeline, "run_tool", side_effect=fake_run_tool), patch.object(
                run_pipeline, "BASE_DIR", tmp_path
            ), patch.object(run_pipeline, "save_state"), patch.object(
                run_pipeline, "log_result"
            ):
                run_pipeline.run_foundation(state)

        self.assertFalse(any("git checkout --" in cmd for cmd in tool_cmds))
        self.assertEqual(state["foundation_score"], 8.0)

    def test_revision_post_eval_timeout_does_not_checkout_chapter(self):
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

        def fake_uv_run(script, timeout=600):
            if "evaluate.py" in script:
                return subprocess.CompletedProcess(
                    script, -1, stdout="", stderr="TIMEOUT"
                )
            return subprocess.CompletedProcess(
                script, 0, stdout="novel_score: 8.0\noverall_score: 8.0\n", stderr=""
            )

        def fake_run_tool(cmd, timeout=600, check=False):
            tool_cmds.append(cmd)
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            chapters = tmp_path / "chapters"
            chapters.mkdir()
            (chapters / "ch_02.md").write_text("revised chapter")
            state = run_pipeline.default_state()
            state["novel_score"] = 7.5
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

        self.assertFalse(any("git checkout -- chapters/ch_02.md" in cmd for cmd in tool_cmds))
        self.assertEqual(state["novel_score"], 7.5)

    def test_revision_empty_eval_stdout_does_not_checkout_chapter(self):
        tool_cmds = []

        def fake_generation(script, timeout):
            if script == "reader_panel.py":
                panel_path = run_pipeline.EDIT_LOGS_DIR / "reader_panel.json"
                panel_path.write_text(json.dumps({
                    "readers": {},
                    "disagreements": [{
                        "chapter": 3,
                        "question": "cut_candidate",
                        "flagged_by": ["r1", "r2", "r3"],
                    }],
                }))

        def fake_uv_run(script, timeout=600):
            if "evaluate.py" in script:
                return subprocess.CompletedProcess(script, 0, stdout="", stderr="")
            return subprocess.CompletedProcess(
                script, 0, stdout="novel_score: 8.0\noverall_score: 8.0\n", stderr=""
            )

        def fake_run_tool(cmd, timeout=600, check=False):
            tool_cmds.append(cmd)
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            chapters = tmp_path / "chapters"
            chapters.mkdir()
            (chapters / "ch_03.md").write_text("revised chapter")
            state = run_pipeline.default_state()
            state["novel_score"] = 7.5
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

        self.assertFalse(any("git checkout -- chapters/ch_03.md" in cmd for cmd in tool_cmds))
        self.assertEqual(state["novel_score"], 7.5)
        self.assertNotEqual(state["novel_score"], -1.0)

    def test_failed_drafts_keep_last_attempt_not_head_chapter(self):
        tool_cmds = []
        commits = []
        previous_book = ("previous book chapter from HEAD. " * 8).strip()
        last_draft = {"text": ""}
        drafts = []

        def fake_uv_run(script, timeout=600):
            if script.startswith("draft_chapter.py"):
                text = (
                    f"new book draft attempt {len(drafts) + 1} "
                    "with enough words to pass the short-file check. "
                ) * 4
                last_draft["text"] = text
                drafts.append(text)
                (run_pipeline.CHAPTERS_DIR / "ch_01.md").write_text(text)
                return subprocess.CompletedProcess(script, 0, stdout="", stderr="")
            return subprocess.CompletedProcess(
                script, 0, stdout="overall_score: 3.0\n", stderr=""
            )

        def fake_run_tool(cmd, timeout=600, check=False):
            tool_cmds.append(cmd)
            if "git checkout -- chapters/ch_01.md" in cmd:
                (run_pipeline.CHAPTERS_DIR / "ch_01.md").write_text(previous_book)
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        def fake_commit(message):
            commits.append((message, (run_pipeline.CHAPTERS_DIR / "ch_01.md").read_text()))
            return "abc"

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            chapters = tmp_path / "chapters"
            chapters.mkdir()
            chapter_path = chapters / "ch_01.md"
            chapter_path.write_text(previous_book)
            state = run_pipeline.default_state()
            state["chapters_total"] = 1
            state["chapters_drafted"] = 0
            with patch.object(run_pipeline, "MAX_CHAPTER_ATTEMPTS", 2), patch.object(
                run_pipeline, "uv_run", side_effect=fake_uv_run
            ), patch.object(run_pipeline, "run_tool", side_effect=fake_run_tool), patch.object(
                run_pipeline, "git_add_commit", side_effect=fake_commit
            ), patch.object(run_pipeline, "CHAPTERS_DIR", chapters), patch.object(
                run_pipeline, "save_state"
            ), patch.object(run_pipeline, "log_result"), patch.object(
                run_pipeline, "configured_target_chapters", return_value=1
            ), patch.object(run_pipeline, "BASE_DIR", tmp_path):
                run_pipeline.run_drafting(state)

            self.assertEqual(len(drafts), 2)
            self.assertEqual(chapter_path.read_text(), last_draft["text"])
            self.assertNotIn(previous_book, chapter_path.read_text())
            self.assertTrue(commits)
            self.assertIn("best-effort", commits[-1][0])
            self.assertEqual(commits[-1][1], last_draft["text"])

        self.assertFalse(
            any("git checkout -- chapters/ch_01.md" in cmd for cmd in tool_cmds)
        )

    def test_draft_chapter_prompt_includes_canon(self):
        distinctive = "ZXQ-CANON-SENTENCE: the mill wheel is bronze-bound."
        captured = {}

        def fake_load_file(path):
            name = Path(path).name
            if name == "canon.md":
                return distinctive
            if name == "outline.md":
                return "### Chapter 1: Opening\n- Beat one\n"
            return "stub"

        def fake_writer(prompt, max_tokens=16000):
            captured["prompt"] = prompt
            return "chapter draft text"

        with tempfile.TemporaryDirectory() as tmp:
            chapters = Path(tmp) / "chapters"
            with patch.object(draft_chapter, "load_file", side_effect=fake_load_file), patch.object(
                draft_chapter, "call_writer", side_effect=fake_writer
            ), patch.object(draft_chapter, "CHAPTERS_DIR", chapters), patch(
                "draft_chapter.load_book",
                return_value={"title": "T", "pointOfView": "third", "tense": "past"},
            ), patch("draft_chapter.load_seed", return_value="seed"), patch(
                "draft_chapter.target_words_per_chapter", return_value=1000
            ), patch.object(sys, "argv", ["draft_chapter.py", "1"]):
                draft_chapter.main()

        prompt = captured["prompt"]
        self.assertIn(distinctive, prompt)
        self.assertIn("CANON (established hard facts -- violations are bugs):", prompt)

    def test_gen_revision_prompt_includes_canon(self):
        distinctive = "ZXQ-CANON-SENTENCE: the mill wheel is bronze-bound."
        captured = {}

        def fake_writer(prompt, max_tokens=16000):
            captured["prompt"] = prompt
            return "revised chapter"

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            (tmp_path / "voice.md").write_text("voice")
            (tmp_path / "characters.md").write_text("chars")
            (tmp_path / "world.md").write_text("world")
            (tmp_path / "canon.md").write_text(distinctive)
            (tmp_path / "chapters").mkdir()
            brief = tmp_path / "brief.md"
            brief.write_text("fix pacing")
            with patch.object(gen_revision, "BASE_DIR", tmp_path), patch.object(
                gen_revision, "call_writer", side_effect=fake_writer
            ), patch(
                "gen_revision.load_book", return_value={"title": "T"}
            ), patch(
                "gen_revision.load_seed", return_value="seed"
            ), patch.object(sys, "argv", ["gen_revision.py", "1", str(brief)]):
                gen_revision.main()

        prompt = captured["prompt"]
        self.assertIn(distinctive, prompt)
        self.assertIn("CANON (established hard facts -- violations are bugs):", prompt)

    def test_kept_chapter_appends_new_canon_entries(self):
        distinctive = "ZXQ-NEW-FACT: the mill token sinks in the race."
        canon_at_ch2 = {}

        def fake_uv_run(script, timeout=600):
            if script.startswith("draft_chapter.py"):
                if script.endswith(" 2"):
                    canon_at_ch2["text"] = (run_pipeline.BASE_DIR / "canon.md").read_text()
                ch = int(script.split()[-1])
                text = "kept chapter body with enough words to pass. " * 8
                (run_pipeline.CHAPTERS_DIR / f"ch_{ch:02d}.md").write_text(text)
                return subprocess.CompletedProcess(script, 0, stdout="", stderr="")
            if "evaluate.py --chapter=" in script:
                ch = int(script.split("=", 1)[1])
                payload = {
                    "overall_score": 7.0,
                    "new_canon_entries": (
                        [distinctive, distinctive, "", "  "] if ch == 1 else []
                    ),
                }
                logs = run_pipeline.BASE_DIR / "eval_logs"
                logs.mkdir(exist_ok=True)
                (logs / f"20260101_00000{ch}_ch{ch:02d}.json").write_text(
                    json.dumps(payload)
                )
                return subprocess.CompletedProcess(
                    script, 0, stdout="overall_score: 7.0\n", stderr=""
                )
            return subprocess.CompletedProcess(script, 0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            chapters = tmp_path / "chapters"
            chapters.mkdir()
            canon = tmp_path / "canon.md"
            canon.write_text("# Canon\n\nExisting fact.\n")
            state = run_pipeline.default_state()
            state["chapters_total"] = 2
            state["chapters_drafted"] = 0
            with patch.object(run_pipeline, "uv_run", side_effect=fake_uv_run), patch.object(
                run_pipeline, "git_add_commit", return_value="abc"
            ), patch.object(run_pipeline, "CHAPTERS_DIR", chapters), patch.object(
                run_pipeline, "save_state"
            ), patch.object(run_pipeline, "log_result"), patch.object(
                run_pipeline, "configured_target_chapters", return_value=2
            ), patch.object(run_pipeline, "BASE_DIR", tmp_path):
                run_pipeline.run_drafting(state)

            text = canon.read_text()
            self.assertIn(distinctive, text)
            self.assertEqual(text.count(distinctive), 1)
            self.assertIn("Existing fact.", text)

        self.assertIn(distinctive, canon_at_ch2.get("text", ""))

    def test_best_effort_keep_skips_stale_eval_canon_entries(self):
        distinctive = "ZXQ-STALE-FACT: the prior attempt named the mill token."
        eval_calls = {"n": 0}

        def fake_uv_run(script, timeout=600):
            if script.startswith("draft_chapter.py"):
                text = (
                    f"best-effort draft attempt {eval_calls['n'] + 1} "
                    "with enough words to pass the short-file check. "
                ) * 4
                (run_pipeline.CHAPTERS_DIR / "ch_01.md").write_text(text)
                return subprocess.CompletedProcess(script, 0, stdout="", stderr="")
            if "evaluate.py --chapter=" in script:
                eval_calls["n"] += 1
                if eval_calls["n"] == 1:
                    payload = {
                        "overall_score": 3.0,
                        "new_canon_entries": [distinctive],
                    }
                    logs = run_pipeline.BASE_DIR / "eval_logs"
                    logs.mkdir(exist_ok=True)
                    (logs / "20260101_000001_ch01.json").write_text(
                        json.dumps(payload)
                    )
                    return subprocess.CompletedProcess(
                        script, 0, stdout="overall_score: 3.0\n", stderr=""
                    )
                return subprocess.CompletedProcess(
                    script, -1, stdout="", stderr="TIMEOUT"
                )
            return subprocess.CompletedProcess(script, 0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            chapters = tmp_path / "chapters"
            chapters.mkdir()
            canon = tmp_path / "canon.md"
            canon.write_text("# Canon\n\nExisting fact.\n")
            state = run_pipeline.default_state()
            state["chapters_total"] = 1
            state["chapters_drafted"] = 0
            with patch.object(run_pipeline, "MAX_CHAPTER_ATTEMPTS", 2), patch.object(
                run_pipeline, "uv_run", side_effect=fake_uv_run
            ), patch.object(run_pipeline, "git_add_commit", return_value="abc"), patch.object(
                run_pipeline, "CHAPTERS_DIR", chapters
            ), patch.object(run_pipeline, "save_state"), patch.object(
                run_pipeline, "log_result"
            ), patch.object(
                run_pipeline, "configured_target_chapters", return_value=1
            ), patch.object(run_pipeline, "BASE_DIR", tmp_path):
                run_pipeline.run_drafting(state)

            self.assertEqual(eval_calls["n"], 2)
            self.assertNotIn(distinctive, canon.read_text())
            self.assertIn("Existing fact.", canon.read_text())

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

    def test_run_revision_uses_review_briefs_not_auto(self):
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
            if "gen_brief.py --review" in cmd:
                (run_pipeline.BRIEFS_DIR / "ch08_review.md").write_text(
                    "# Revision Brief: Chapter 8 (REVIEW)\n"
                )
                leftover = run_pipeline.BRIEFS_DIR / "ch03_review.md"
                leftover.write_text("# leftover other-chapter review brief\n")
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            (tmp_path / "review.py").write_text("")
            (tmp_path / "gen_brief.py").write_text("")
            (tmp_path / "20260101_review.json").write_text(json.dumps({
                "stars": 3.0,
                "total_items": 5,
                "major_items": 3,
                "qualified_items": 1,
                "professor_items": [
                    {
                        "number": 1,
                        "title": "Chapter 8 pacing collapse",
                        "severity": "major",
                        "type": "revision",
                        "qualified": False,
                        "suggestion": "Tighten the midpoint of Chapter 8.",
                        "full_text": "The midpoint of Chapter 8 stalls.",
                    },
                    {
                        "number": 2,
                        "title": "Thin antagonist",
                        "severity": "major",
                        "type": "revision",
                        "qualified": False,
                        "suggestion": "Give the antagonist a private cost.",
                        "full_text": "The antagonist never chooses.",
                    },
                    {
                        "number": 3,
                        "title": "Opening echo",
                        "severity": "minor",
                        "type": "line-edit",
                        "qualified": True,
                        "suggestion": "Trim one repeated image.",
                        "full_text": "Mostly fine.",
                    },
                ],
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

        self.assertTrue(
            any("gen_brief.py --review 8" in cmd for cmd in tool_cmds)
        )
        self.assertFalse(any("gen_brief.py --auto" in cmd for cmd in tool_cmds))
        revision_cmds = [s for s in uv_scripts if s.startswith("gen_revision.py 8 ")]
        self.assertTrue(revision_cmds)
        self.assertTrue(any("ch08_review.md" in s for s in revision_cmds))
        self.assertFalse(any("ch03_review.md" in s for s in uv_scripts))

    def test_run_revision_ignores_stale_review_json_when_review_py_fails(self):
        uv_scripts = []

        def fake_generation(script, timeout):
            if script == "reader_panel.py":
                panel_path = run_pipeline.EDIT_LOGS_DIR / "reader_panel.json"
                panel_path.write_text(json.dumps({"readers": {}, "disagreements": []}))

        def fake_uv_run(script, timeout=600):
            uv_scripts.append(script)
            if "review.py" in script:
                return subprocess.CompletedProcess(
                    script, -1, stdout="", stderr="TIMEOUT"
                )
            return subprocess.CompletedProcess(
                script, 0, stdout="novel_score: 8.0\noverall_score: 8.0\n", stderr=""
            )

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
            ), patch.object(run_pipeline, "run_tool", return_value=subprocess.CompletedProcess(
                "", 0, stdout="", stderr=""
            )), patch.object(run_pipeline, "BASE_DIR", tmp_path), patch.object(
                run_pipeline, "EDIT_LOGS_DIR", tmp_path
            ), patch.object(run_pipeline, "BRIEFS_DIR", tmp_path), patch.object(
                run_pipeline, "save_state"
            ), patch.object(run_pipeline, "git_add_commit", return_value="abc"), patch.object(
                run_pipeline, "log_result"
            ), patch.object(run_pipeline, "count_words_in_chapters", return_value=0):
                run_pipeline.run_revision(state, max_cycles=1)

        self.assertEqual(len([s for s in uv_scripts if "review.py" in s]), 4)
        self.assertFalse(any("gen_revision.py" in s for s in uv_scripts))

    def test_run_revision_skips_revision_when_gen_brief_fails(self):
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
            if "gen_brief.py --review" in cmd:
                return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="fail")
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            (tmp_path / "review.py").write_text("")
            (tmp_path / "gen_brief.py").write_text("")
            (tmp_path / "ch08_review.md").write_text("# leftover review brief\n")
            (tmp_path / "20260101_review.json").write_text(json.dumps({
                "stars": 3.0,
                "total_items": 5,
                "major_items": 3,
                "qualified_items": 1,
                "professor_items": [
                    {
                        "number": 1,
                        "title": "Chapter 8 pacing collapse",
                        "severity": "major",
                        "type": "revision",
                        "qualified": False,
                        "suggestion": "Tighten the midpoint of Chapter 8.",
                        "full_text": "The midpoint of Chapter 8 stalls.",
                    },
                ],
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

        self.assertTrue(any("gen_brief.py --review 8" in cmd for cmd in tool_cmds))
        self.assertFalse(any("gen_revision.py" in s for s in uv_scripts))

    def test_all_chapter_tools_follow_chapter_numbers(self):
        present = [1, 2, 18, 30]
        sample = (
            "The bronze bells rang across the square. She walked toward the workshop "
            "and kept her hands in the linseed oil."
        )
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            chapters_dir = tmp_path / "chapters"
            chapters_dir.mkdir()
            (tmp_path / "edit_logs").mkdir()
            for number in present:
                (chapters_dir / f"ch_{number:02d}.md").write_text(sample)

            with patch.object(book_config, "BASE_DIR", tmp_path), patch.object(
                adversarial_edit, "CHAPTERS_DIR", chapters_dir
            ), patch.object(
                voice_fingerprint, "CHAPTERS_DIR", chapters_dir
            ), patch.object(
                voice_fingerprint, "BASE_DIR", tmp_path
            ), patch.object(
                compare_chapters, "BASE_DIR", tmp_path
            ), patch.object(
                adversarial_edit, "edit_chapter", return_value=(
                    {
                        "cuts": [],
                        "total_cuttable_words": 0,
                        "overall_fat_percentage": 0,
                        "one_sentence_verdict": "ok",
                    },
                    12,
                )
            ) as mock_edit:
                self.assertEqual(run_drafts.chapters_to_draft(), present)
                with patch.object(sys, "argv", ["adversarial_edit.py", "all"]):
                    adversarial_edit.main()
                self.assertEqual(
                    [call.args[0] for call in mock_edit.call_args_list], present
                )

                voice_fingerprint.main()
                fingerprint = json.loads(
                    (tmp_path / "edit_logs" / "voice_fingerprint.json").read_text()
                )
                chapter_keys = sorted(
                    key for key in fingerprint["chapters"] if key != "novel_average"
                )
                self.assertEqual(
                    chapter_keys, [f"ch_{number:02d}" for number in present]
                )

                with patch.object(
                    compare_chapters, "run_tournament", return_value=(
                        present,
                        {number: 1500 for number in present},
                        [],
                    )
                ) as mock_tournament, patch.object(
                    sys, "argv", ["compare_chapters.py"]
                ):
                    compare_chapters.main()
                mock_tournament.assert_called_once_with(present)

                with patch.object(
                    gen_audiobook_script, "SCRIPTS_DIR", tmp_path / "audiobook" / "scripts"
                ), patch.object(
                    gen_audiobook_script, "parse_chapter", return_value=None
                ) as mock_parse, patch.object(
                    sys, "argv", ["gen_audiobook_script.py"]
                ):
                    gen_audiobook_script.main()
                self.assertEqual(
                    [call.args[0] for call in mock_parse.call_args_list], present
                )

    def test_parse_chapter_prompt_uses_characters_md_not_demo_cast(self):
        captured = {}

        def fake_call_model(prompt, max_tokens=8000):
            captured["prompt"] = prompt
            return json.dumps([
                {"speaker": "NARRATOR", "text": "Chapter One"},
                {"speaker": "Mira", "text": "Hello"},
            ])

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            chapters_dir = tmp_path / "chapters"
            chapters_dir.mkdir()
            (tmp_path / "characters.md").write_text(
                "# Characters\n\n"
                "<!-- For each character:\n"
                "## Name (POV / non-POV)\n"
                "- Role:\n-->\n\n"
                "## Mira (POV)\n- Role: scout\n- Speech pattern: clipped\n\n"
                "## Kael (non-POV)\n- Role: smith\n"
            )
            (chapters_dir / "ch_01.md").write_text("# Chapter One\n\nMira spoke.\n")

            with patch.object(gen_audiobook_script, "BASE_DIR", tmp_path), patch.object(
                gen_audiobook_script, "CHAPTERS_DIR", chapters_dir
            ), patch.object(
                gen_audiobook_script, "call_model", side_effect=fake_call_model
            ):
                result = gen_audiobook_script.parse_chapter(1)

        self.assertIsNotNone(result)
        prompt = captured["prompt"]
        self.assertIn("Mira", prompt)
        self.assertIn("Kael", prompt)
        self.assertNotIn("CASS", prompt)
        self.assertNotIn("EDDAN", prompt)
        self.assertNotIn("Cass usually", prompt)
        roster = json.loads(
            prompt.split("CHARACTERS IN THIS NOVEL:\n", 1)[1].split("\n\nAUDIO TAG GUIDE:", 1)[0]
        )
        self.assertIn("NARRATOR", roster)
        self.assertIn("Mira", roster)
        self.assertIn("Kael", roster)
        self.assertNotIn("Name", roster)

    def test_extract_chapter_outline_accepts_chapter_heading(self):
        result = draft_chapter.extract_chapter_outline(
            "### Chapter 1: A\nbeats\n### Chapter 2: B\n", 1
        )
        self.assertNotEqual(result, "(not found)")
        self.assertIn("Chapter 1", result)
        self.assertIn("beats", result)
        self.assertNotIn("Chapter 2", result)

    def test_extract_chapter_outline_stops_at_next_heading_any_number(self):
        outline = "### Ch 1: A\n### Ch 7: B\n### Ch 18: C\n"
        chapter_1 = draft_chapter.extract_chapter_outline(outline, 1)
        self.assertIn("Ch 1", chapter_1)
        self.assertNotIn("Ch 7", chapter_1)
        self.assertNotIn("Ch 18", chapter_1)
        chapter_7 = draft_chapter.extract_chapter_outline(outline, 7)
        self.assertIn("Ch 7", chapter_7)
        self.assertNotIn("Ch 18", chapter_7)

    def test_get_total_chapters_uses_outline_max_not_prefilled_state(self):
        def fake_uv_run(script, timeout=600):
            return subprocess.CompletedProcess(
                script, 0, stdout="overall_score: 8.0\nlore_score: 8.0\n", stderr=""
            )

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            (tmp_path / "outline.md").write_text(
                "### Ch 1: Opening\n\n### Ch 7: Mid\n\n### Ch 18: Close\n"
            )
            state = run_pipeline.default_state()
            state["chapters_total"] = 24
            with patch.object(run_pipeline, "BASE_DIR", tmp_path):
                self.assertEqual(run_pipeline.get_total_chapters(state), 18)
                with patch.object(run_pipeline, "run_generation"), patch.object(
                    run_pipeline, "uv_run", side_effect=fake_uv_run
                ), patch.object(run_pipeline, "save_state"), patch.object(
                    run_pipeline, "git_add_commit", return_value="abc"
                ), patch.object(run_pipeline, "log_result"):
                    result = run_pipeline.run_foundation(state)
            self.assertEqual(result["chapters_total"], 18)

    def test_get_total_chapters_falls_back_when_outline_has_no_headings(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            state = {"chapters_total": 99}
            with patch.object(run_pipeline, "BASE_DIR", tmp_path), patch.object(
                run_pipeline, "configured_target_chapters", return_value=24
            ):
                self.assertEqual(run_pipeline.get_total_chapters(state), 24)
            (tmp_path / "outline.md").write_text("Act 1\nNo numbered chapter headings.\n")
            with patch.object(run_pipeline, "BASE_DIR", tmp_path), patch.object(
                run_pipeline, "configured_target_chapters", return_value=24
            ):
                self.assertEqual(run_pipeline.get_total_chapters(state), 24)

    def test_run_drafts_import_does_not_spawn_subprocess(self):
        with patch("subprocess.run") as mock_run:
            importlib.reload(run_drafts)
            mock_run.assert_not_called()
        source = Path(__file__).resolve().parent.parent.joinpath("run_drafts.py").read_text()
        self.assertNotIn("range(11, 25)", source)
        self.assertNotIn("list(range(11, 25))", source)

    def test_chunk_segments_matches_mira_not_minor_and_reports_unknown(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            (tmp_path / "characters.md").write_text(
                "## Mira (POV)\n- Role: scout\n\n## Kael (non-POV)\n- Role: smith\n"
            )
            with patch.object(gen_audiobook_script, "BASE_DIR", tmp_path):
                roster = gen_audiobook_script.load_characters()
        self.assertIn("Mira", roster)
        mira_voice = "mira-voice-id"
        minor_voice = "minor-voice-id"
        voices = {
            "mira": mira_voice,
            "MINOR": minor_voice,
            "NARRATOR": "narrator-voice-id",
        }
        segments = [
            {"speaker": "Mira", "text": "Hello from the ridge."},
            {"speaker": "UnknownGuard", "text": "Halt where you are."},
        ]
        buf = io.StringIO()
        with patch("sys.stdout", buf):
            chunks = gen_audiobook.chunk_segments(segments, voices)
        items = [item for chunk in chunks for item in chunk]
        by_text = {item["text"]: item["voice_id"] for item in items}
        self.assertEqual(by_text["Hello from the ridge."], mira_voice)
        self.assertNotEqual(by_text["Hello from the ridge."], minor_voice)
        self.assertEqual(by_text["Halt where you are."], minor_voice)
        report = buf.getvalue()
        self.assertIn("UnknownGuard", report)
        self.assertNotIn("Mira", report.split("Unknown speakers", 1)[-1])

    def test_gen_audiobook_main_uses_script_chapter_numbers(self):
        def generated_chapters(argv):
            with patch.object(gen_audiobook, "generate_chapter") as mock_generate, patch.object(
                gen_audiobook, "load_voices", return_value={"NARRATOR": "voice"}
            ), patch.object(
                gen_audiobook, "get_client", return_value=MagicMock()
            ), patch.object(
                gen_audiobook, "assemble_full_audiobook"
            ), patch.object(
                sys, "argv", argv
            ):
                gen_audiobook.main()
            return [call.args[0] for call in mock_generate.call_args_list]

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            scripts_dir = tmp_path / "scripts"
            scripts_dir.mkdir()
            for number in (1, 2, 18):
                (scripts_dir / f"ch{number:02d}_script.json").write_text("{}")
            voices_file = tmp_path / "audiobook_voices.json"
            voices_file.write_text(json.dumps({"NARRATOR": {"voice_id": "voice"}}))

            with patch.object(gen_audiobook, "SCRIPTS_DIR", scripts_dir), patch.object(
                gen_audiobook, "VOICES_FILE", voices_file
            ):
                self.assertEqual(generated_chapters(["gen_audiobook.py"]), [1, 2, 18])
                self.assertEqual(generated_chapters(["gen_audiobook.py", "1"]), [1])
                self.assertEqual(
                    generated_chapters(["gen_audiobook.py", "1", "5"]), [1, 2]
                )

    def test_gen_audiobook_assemble_and_status_skip_api_key(self):
        def missing_key_client():
            raise SystemExit(1)

        with patch.dict(os.environ), patch.object(gen_audiobook, "ELEVENLABS_KEY", ""):
            os.environ.pop("ELEVENLABS_API_KEY", None)

            with patch.object(
                gen_audiobook, "get_client", side_effect=missing_key_client
            ) as mock_get_client, patch.object(
                sys, "argv", ["gen_audiobook.py", "--status"]
            ), patch("sys.stdout", io.StringIO()):
                gen_audiobook.main()
            mock_get_client.assert_not_called()

            with patch.object(
                gen_audiobook, "get_client", side_effect=missing_key_client
            ) as mock_get_client, patch.object(
                gen_audiobook, "assemble_full_audiobook"
            ) as mock_assemble, patch.object(
                sys, "argv", ["gen_audiobook.py", "--assemble"]
            ):
                gen_audiobook.main()
            mock_get_client.assert_not_called()
            mock_assemble.assert_called_once()

            with patch.object(
                gen_audiobook, "get_client", side_effect=missing_key_client
            ) as mock_get_client, patch.object(
                sys, "argv", ["gen_audiobook.py", "--list-voices"]
            ):
                with self.assertRaises(SystemExit) as raised:
                    gen_audiobook.main()
                self.assertEqual(raised.exception.code, 1)
                mock_get_client.assert_called_once()

    def test_run_drafts_uses_running_interpreter_not_venv(self):
        source = Path(__file__).resolve().parent.parent.joinpath("run_drafts.py").read_text()
        self.assertNotIn(".venv/bin/python3", source)

        captured = []

        def fake_run(cmd, **kwargs):
            captured.append(cmd)
            if isinstance(cmd, (list, tuple)) and len(cmd) >= 2 and cmd[1] == "-c":
                stdout = json.dumps({
                    "slop_penalty": 0.0,
                    "tier1_hits": [],
                    "fiction_ai_tells": [],
                    "telling_violations": 0,
                })
            else:
                stdout = "overall_score: 7.5\nraw_judge_score: 8\n"
            return subprocess.CompletedProcess(cmd, 0, stdout=stdout, stderr="")

        with patch("run_drafts.subprocess.run", side_effect=fake_run):
            slop = run_drafts.slop_check(1)
            score, raw = run_drafts.spot_eval(2)
            run_drafts.run_python(["draft_chapter.py", "3"])

        self.assertEqual(slop["slop_penalty"], 0.0)
        self.assertEqual(score, 7.5)
        self.assertEqual(raw, 8)
        self.assertEqual(len(captured), 3)
        scripts = []
        for cmd in captured:
            self.assertIsInstance(cmd, (list, tuple))
            self.assertEqual(cmd[0], sys.executable)
            self.assertNotIn(".venv/bin/python3", " ".join(str(part) for part in cmd))
            scripts.append(cmd[1] if len(cmd) > 1 else "")
        self.assertEqual(scripts, ["-c", "evaluate.py", "draft_chapter.py"])

        with tempfile.TemporaryDirectory() as tmp:
            chapters = Path(tmp) / "chapters"
            self.assertFalse(chapters.exists())
            with patch.object(draft_chapter, "CHAPTERS_DIR", chapters), patch.object(
                draft_chapter, "call_writer", return_value="draft body"
            ), patch.object(sys, "argv", ["draft_chapter.py", "4"]):
                draft_chapter.main()
            self.assertTrue(chapters.is_dir())
            self.assertEqual((chapters / "ch_04.md").read_text(), "draft body")

    def test_chapters_to_draft_uses_existing_files_or_target_count(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            chapters_dir = tmp_path / "chapters"
            chapters_dir.mkdir()
            for number in (1, 2, 18, 30):
                (chapters_dir / f"ch_{number:02d}.md").write_text("x")
            with patch.object(book_config, "BASE_DIR", tmp_path):
                self.assertEqual(run_drafts.chapters_to_draft(), [1, 2, 18, 30])

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            (tmp_path / "chapters").mkdir()
            (tmp_path / "book.json").write_text(json.dumps({"targetChapters": 18}))
            with patch.object(book_config, "BASE_DIR", tmp_path):
                self.assertEqual(run_drafts.chapters_to_draft(), list(range(1, 19)))

    def test_apply_cuts_rewrite_substitutes_instead_of_deleting(self):
        span_rewrite = (
            "She explained the entire clockwork in exhausting detail yet again."
        )
        span_cut = "The same fact was restated here without adding anything useful."
        span_empty = (
            "This over-explained beat must remain if empty rewrite skips it."
        )
        rewrite = "She glanced at the clockwork."
        original = (
            "Opening line stays put.\n\n"
            f"{span_rewrite}\n\n"
            f"{span_cut}\n\n"
            f"{span_empty}\n"
        )
        cuts = {
            "overall_fat_percentage": 20,
            "cuts": [
                {
                    "quote": span_rewrite,
                    "type": "OVER-EXPLAIN",
                    "reason": "narrator restates the scene",
                    "action": "REWRITE",
                    "rewrite": rewrite,
                },
                {
                    "quote": span_cut,
                    "type": "REDUNDANT",
                    "reason": "already shown",
                    "action": "CUT",
                    "rewrite": None,
                },
                {
                    "quote": span_empty,
                    "type": "OVER-EXPLAIN",
                    "reason": "would rewrite if text existed",
                    "action": "REWRITE",
                    "rewrite": "",
                },
            ],
        }

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            chapters = tmp_path / "chapters"
            logs = tmp_path / "edit_logs"
            chapters.mkdir()
            logs.mkdir()
            chapter_file = chapters / "ch_01.md"
            chapter_file.write_text(original)
            (logs / "ch01_cuts.json").write_text(json.dumps(cuts))

            with patch.object(apply_cuts, "CHAPTERS_DIR", chapters), patch.object(
                apply_cuts, "EDIT_LOGS_DIR", logs
            ):
                dry_buf = io.StringIO()
                with patch("sys.stdout", dry_buf):
                    dry_stats = apply_cuts.process_chapter(1, None, 0, True)
                self.assertEqual(chapter_file.read_text(), original)
                dry_out = dry_buf.getvalue()
                self.assertIn("REPLACE", dry_out)
                self.assertRegex(dry_out, r"\bCUT\b")
                self.assertEqual(dry_stats["applied"], 2)
                self.assertEqual(dry_stats["skipped"], 1)

                apply_buf = io.StringIO()
                with patch("sys.stdout", apply_buf):
                    stats = apply_cuts.process_chapter(1, None, 0, False)

            result = chapter_file.read_text()
            expected = apply_cuts.collapse_blank_lines(
                original.replace(span_rewrite, rewrite).replace(span_cut, "")
            )
            self.assertEqual(result, expected)
            self.assertIn(rewrite, result)
            self.assertNotIn(span_rewrite, result)
            self.assertNotIn(span_cut, result)
            self.assertIn(span_empty, result)
            self.assertEqual(stats["applied"], 2)
            self.assertEqual(stats["skipped"], 1)
            self.assertEqual(stats["failed"], 0)
            self.assertIn("REPLACE", apply_buf.getvalue())

        pipeline_src = Path(__file__).resolve().parent.parent.joinpath(
            "run_pipeline.py"
        ).read_text()
        self.assertIn("uv run python apply_cuts.py all", pipeline_src)
        self.assertIn("--types OVER-EXPLAIN REDUNDANT", pipeline_src)

    def test_build_tex_updates_chapters_without_clobbering_novel_wrapper(self):
        import importlib.util

        spec = importlib.util.spec_from_file_location(
            "build_tex",
            Path(__file__).resolve().parent.parent / "typeset" / "build_tex.py",
        )
        build_tex = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(build_tex)

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            chapters = tmp_path / "chapters"
            typeset_dir = tmp_path / "typeset"
            chapters.mkdir()
            typeset_dir.mkdir()
            novel_tex = typeset_dir / "novel.tex"
            novel_tex.write_text(
                "\\makenoveltitle\n\\input{chapters_content.tex}\n"
            )
            original = novel_tex.read_bytes()
            (chapters / "ch_01.md").write_text(
                "# Chapter 1: The Opening\n\nFirst scene.\n---\nSecond scene.\n"
            )
            with patch.object(build_tex, "BASE_DIR", tmp_path), patch.object(
                build_tex, "CHAPTERS_DIR", chapters
            ), patch.object(build_tex, "OUT_DIR", typeset_dir):
                build_tex.main()

            self.assertEqual(novel_tex.read_bytes(), original)
            self.assertIn("\\makenoveltitle", novel_tex.read_text())
            self.assertIn("\\input{chapters_content.tex}", novel_tex.read_text())
            content = (typeset_dir / "chapters_content.tex").read_text()
            self.assertIn("\\chapter{", content)
            self.assertIn("\\scenebreak", content)


if __name__ == "__main__":
    unittest.main()

