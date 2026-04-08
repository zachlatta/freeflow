# FreeFlow Prompt Eval

This directory vendors the prompt-evaluation harness used to tune FreeFlow's context and dictation-cleanup prompts.

It is a curated import from the standalone `freeflow-eval` repo, not the full archive.

Included here:

- `eval_groq_prompts.py`: standalone runner
- `tests/test_eval_groq_prompts.py`: regression tests for scoring and CLI parsing
- `eval/prompt_variants.json`: context and system prompt variants, including the current `v24` candidate
- `eval/prompt_eval_cases*.json`: main fixture suites
- `eval/results/`: only two representative saved comparisons

Deliberately excluded:

- temporary focused case files under `eval/tmp_*.json`
- the larger historical results archive
- miscellaneous local-only files like `.env.local` and caches

## Included Result Artifacts

This repo only keeps these result snapshots:

- `eval/results/original-vs-baseline-vs-v24-concurrency30-2026-04-01.json`
- `eval/results/original-vs-baseline-vs-v24-concurrency30-2026-04-01.md`
- `eval/results/model-compare-v24-hybrid-gpt54nano-judge-2026-04-05.json`
- `eval/results/model-compare-v24-hybrid-gpt54nano-judge-2026-04-05.md`

Those cover:

- `v24` vs the older baseline prompts on the 32-case English-context suite
- `openai/gpt-oss-20b` vs `meta-llama/llama-4-scout` on `v24`

## Current Read

The imported artifacts support this working recommendation:

- Model: `openai/gpt-oss-20b`
- System prompt candidate: `system-gptoss-multilingual-email-v24`

The app's shipped defaults live in [`../Sources/PostProcessingService.swift`](../Sources/PostProcessingService.swift) and [`../Sources/AppContextService.swift`](../Sources/AppContextService.swift). This eval harness is for prompt iteration and comparison, not the app runtime itself.

## What The Runner Supports

- `context`, `postprocess`, and `pipeline` modes
- OpenAI-compatible chat APIs via `--base-url`
- Groq direct and OpenRouter
- optional OpenRouter provider controls
- heuristic, LLM-judge, and hybrid scoring
- separate judge-model selection with `--judge-model`
- screenshot-backed context evals when a case has `screenshot_path`
- parallel case execution with `--max-concurrency`

## Quick Start

The harness uses only the Python standard library.

From this directory:

```bash
python3 -m unittest discover -s tests -v
```

Example `v24` vs baseline run:

```bash
python3 eval_groq_prompts.py \
  --api-key "$OPENROUTER_API_KEY" \
  --base-url https://openrouter.ai/api/v1 \
  --mode postprocess \
  --cases eval/prompt_eval_cases_system_only_en_context.json \
  --models openai/gpt-oss-20b \
  --system-variants user-baseline-system system-gptoss-multilingual-email-v24 \
  --scoring-mode hybrid \
  --judge-model openai/gpt-5.4-nano \
  --min-request-interval 0 \
  --max-concurrency 6 \
  --output-json eval/results/example-v24-vs-baseline.json
```

Example model comparison on `v24`:

```bash
python3 eval_groq_prompts.py \
  --api-key "$OPENROUTER_API_KEY" \
  --base-url https://openrouter.ai/api/v1 \
  --mode postprocess \
  --cases eval/prompt_eval_cases_system_only_en_context.json \
  --models openai/gpt-oss-20b meta-llama/llama-4-scout \
  --system-variants system-gptoss-multilingual-email-v24 \
  --scoring-mode hybrid \
  --judge-model openai/gpt-5.4-nano \
  --min-request-interval 0 \
  --max-concurrency 6 \
  --output-json eval/results/example-model-compare-v24.json
```
