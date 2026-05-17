# OpenAI BYOK Migration Map

This map was produced before code migration, per the OpenAI BYOK execution plan.
It lists every Anthropic-shaped LLM call site found in the current codebase,
plus nearby modules checked during recon.

## Recon Scope

- Read `PIPELINE.md`, including the Phase 3b Opus review loop.
- Read `run_pipeline.py`, `seed.py`, and every `gen_*.py` file.
- Searched for `client.py`, `llm.py`, and `anthropic_*.py`; none exist in this checkout.
- Searched Python sources for Anthropic API keys, Claude model names, `/v1/messages`,
  `httpx.post`, and message payload construction.

## Shared Anthropic Shape To Remove

Most call sites duplicate the same pattern:

- Env key: `ANTHROPIC_API_KEY`
- Base URL env: `AUTONOVEL_API_BASE_URL`, defaulting to `https://api.anthropic.com`
- Endpoint: `POST {base}/v1/messages`
- Headers: `x-api-key`, `anthropic-version`, sometimes `anthropic-beta`
- Payload: `model`, `max_tokens`, `temperature`, optional top-level `system`,
  `messages=[{"role": "user", "content": prompt}]`
- Response extraction: `resp.json()["content"][0]["text"]`

The migration target is a single OpenAI-shaped module exposing `complete(...)`
with plain chat messages, env/runtime API key override, base URL override,
writer/reviewer model slots, and retry handling for rate-limit/connection errors.

## LLM Call Sites

| File | Function | Current model/env/default | Message shape | Migration notes |
| --- | --- | --- | --- | --- |
| `seed.py` | `call_writer(prompt, max_tokens=4000)` | `AUTONOVEL_WRITER_MODEL`, default `claude-sonnet-4-6-20250217` | Top-level system prompt for seed generation; one user message containing concept generation/riff prompt; `temperature=1.0`; `anthropic-beta=context-1m-2025-08-07` | Route to writer slot. Convert top-level system into a `system` role message. CLI missing-key check should require `OPENAI_API_KEY`. |
| `gen_world.py` | `call_writer(prompt, max_tokens=16000)` | `AUTONOVEL_WRITER_MODEL`, default `claude-sonnet-4-6` | Top-level system prompt for fantasy worldbuilding; one user message with seed, voice, craft constraints; `temperature=0.7` | Route to writer slot. Preserve prompt content. |
| `gen_characters.py` | `call_writer(prompt, max_tokens=16000)` | `AUTONOVEL_WRITER_MODEL`, default `claude-sonnet-4-6` | Top-level system prompt for character design; one user message with seed/world/voice; `temperature=0.7` | Route to writer slot. Preserve prompt content. |
| `gen_outline.py` | `call_writer(prompt, max_tokens=16000)` | `AUTONOVEL_WRITER_MODEL`, default `claude-sonnet-4-6` | Top-level system prompt for novel architecture; one user message with seed, mystery, world, characters, voice, craft; `temperature=0.5`; `anthropic-beta=context-1m-2025-08-07` | Route to writer slot. Preserve prompt content. |
| `gen_outline_part2.py` | `call_writer(prompt, max_tokens=16000)` | `AUTONOVEL_WRITER_MODEL`, default `claude-sonnet-4-6` | Top-level system prompt for continuing outline; one user message with partial outline and mystery; `temperature=0.5` | Route to writer slot. Preserve prompt content. |
| `gen_canon.py` | `call_writer(prompt, max_tokens=16000)` | `AUTONOVEL_WRITER_MODEL`, default `claude-sonnet-4-6` | Top-level system prompt for continuity extraction; one user message with source docs; `temperature=0.2` | Route to writer slot. Preserve prompt content and low temperature. |
| `draft_chapter.py` | `call_writer(prompt, max_tokens=16000)` | `AUTONOVEL_WRITER_MODEL`, default `claude-sonnet-4-6` | Top-level system prompt for chapter drafting; one user message with chapter context; `temperature=0.8`; `anthropic-beta=context-1m-2025-08-07` | Route to writer slot. Preserve creative prompt exactly. |
| `gen_revision.py` | `call_writer(prompt, max_tokens=16000)` | `AUTONOVEL_WRITER_MODEL`, default `claude-sonnet-4-6` | Top-level system prompt for revising a chapter from a brief; one user message; `temperature=0.8`; `anthropic-beta=context-1m-2025-08-07` | Route to writer slot. Preserve revision behavior. |
| `build_arc_summary.py` | `call_writer(prompt, max_tokens=4000)` | `AUTONOVEL_WRITER_MODEL`, default `claude-sonnet-4-6` | No system prompt; one user message per chapter or summary task; `temperature=0.1` | Route to writer slot. Keep deterministic temperature. |
| `build_outline.py` | `call_model(prompt, max_tokens=1500)` | `AUTONOVEL_JUDGE_MODEL`, default `claude-sonnet-4-6` | No system prompt; one user message; `temperature=0.1` | Route through reviewer slot because this is a reconstruction/judgment helper, or keep explicit model override if CLI exposes it. |
| `evaluate.py` | `call_judge(prompt, max_tokens=2000)` | `AUTONOVEL_JUDGE_MODEL`, default `claude-opus-4-6` | No system prompt; one user message; `temperature=0.3`; `anthropic-beta=context-1m-2025-08-07` | Route through reviewer slot. Used by `evaluate_foundation`, chapter evaluation, and full novel evaluation. Preserve parser expectations. |
| `adversarial_edit.py` | `call_judge(prompt, max_tokens=8000)` | `AUTONOVEL_JUDGE_MODEL`, default `claude-opus-4-6` | No system prompt; one user message; `temperature=0.3` | Route through reviewer slot. Preserve JSON-ish output expectations. |
| `compare_chapters.py` | `call_judge(prompt, max_tokens=4000)` | `AUTONOVEL_JUDGE_MODEL`, default `claude-opus-4-6` | No system prompt; one user message for pairwise comparison; `temperature=0.2` | Route through reviewer slot. Preserve tournament output parser expectations. |
| `reader_panel.py` | `call_reader(reader_key, arc_summary)` | `AUTONOVEL_JUDGE_MODEL`, default `claude-opus-4-6` | No system prompt; one user message assembled from reader persona plus arc summary; `temperature=0.7` | Route through reviewer slot. Preserve the four personas and their prompts. |
| `review.py` | `call_opus(prompt, max_tokens=8000)` | `AUTONOVEL_REVIEW_MODEL`, default `claude-opus-4-6` | No system prompt; one user message containing full manuscript and dual-persona instruction; `temperature=0.3`; `anthropic-beta=context-1m-2025-08-07` | Required final review migration. Route through `REVIEWER_MODEL`. Preserve the two-persona prompt: literary critic first, professor of fiction second. |
| `gen_art.py` | `call_claude(prompt, max_tokens=1500)` | `AUTONOVEL_WRITER_MODEL`, default `claude-sonnet-4-6` | No system prompt; one user message for visual style JSON generation; `temperature=0.3` | Route through writer slot. FAL image calls in this file are not Anthropic and should stay as-is. |
| `gen_art_directions.py` | `call_claude(prompt, max_tokens=3000)` | `AUTONOVEL_WRITER_MODEL`, default `claude-sonnet-4-6` | No system prompt; one user message for JSON art-direction generation; `temperature=0.9` | Route through writer slot. Preserve JSON extraction cleanup. |
| `gen_audiobook_script.py` | `call_claude(prompt, max_tokens=8000)` | `AUTONOVEL_WRITER_MODEL`, default `claude-sonnet-4-6` | No system prompt; one user message requesting speaker-attributed JSON; `temperature=0.1`; `anthropic-beta=context-1m-2025-08-07` | Route through writer slot. ElevenLabs synthesis remains untouched. |

## Non-LLM Orchestration / Helper Files Checked

- `run_pipeline.py`: no direct LLM call, but orchestrates all LLM tools and contains
  Phase 3b labels/messages referring to Opus. It must be refactored later into
  importable pipeline functions and update labels to OpenAI/reviewer terminology.
- `run_drafts.py`: orchestration wrapper around `draft_chapter.py`; no direct LLM call.
- `gen_brief.py`: deterministic brief generation from local JSON/chapter artifacts;
  no direct LLM call.
- `voice_fingerprint.py`: deterministic prose metrics; no direct LLM call.
- `gen_cover_print.py` and `gen_cover_composite.py`: no LLM call, but default author
  metadata says `Claude Hermes`. That is a historical/content metadata string, not an
  API dependency; decide later whether README/docs should explain or default-change it.

## Dependency And Config Changes Needed

- Remove `anthropic` references from code/config.
- Add `openai` to `pyproject.toml`.
- Keep `httpx` if still needed for FAL, ElevenLabs, SSE clients, or other helpers.
- Update `.env.example`:
  - Remove `ANTHROPIC_API_KEY`.
  - Add `OPENAI_API_KEY`.
  - Add optional `OPENAI_BASE_URL`.
  - Add `WRITER_MODEL`, default `gpt-4o`.
  - Add `REVIEWER_MODEL`, default `gpt-4o`.
  - Preserve `FAL_KEY` and `ELEVENLABS_API_KEY`.

## Open Questions / Risk Notes

- Some call sites expect very large outputs (`max_tokens=16000`) and long context.
  Smoke tests should use small targets and a cheap model, but production defaults
  need clear user-facing model controls.
- The current code uses environment names prefixed with `AUTONOVEL_`; the spec
  asks for `WRITER_MODEL` and `REVIEWER_MODEL`. The migration should prefer the
  spec names while optionally accepting legacy names during transition only if
  it does not leave Anthropic references.
- `PIPELINE.md`, `README.md`, and `WORKFLOW.md` contain Anthropic/Claude historical
  wording and must be updated after the code migration. Historical docs/changelog
  references are allowed by the definition of done, but setup/runtime docs should
  use OpenAI BYOK terminology.
