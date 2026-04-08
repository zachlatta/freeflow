# v24 Model Comparison

Date: 2026-04-05

## Setup

- Cases: `eval/prompt_eval_cases_system_only_en_context.json` (`32` cases)
- Mode: `postprocess`
- System variant: `system-gptoss-multilingual-email-v24`
- Candidate models:
  - `openai/gpt-oss-20b`
  - `meta-llama/llama-4-scout`
- Scoring: `hybrid`
- LLM judge: `openai/gpt-5.4-nano`
- Base URL: `https://openrouter.ai/api/v1`
- Routing: OpenRouter default throughput routing (`provider.sort=throughput`)
- JSON artifact: `eval/results/model-compare-v24-hybrid-gpt54nano-judge-2026-04-05.json`

Command used:

```bash
source .env.local && python3 eval_groq_prompts.py \
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
  --output-json eval/results/model-compare-v24-hybrid-gpt54nano-judge-2026-04-05.json
```

## Summary

| Model | Avg hybrid score | Cases |
| --- | ---: | ---: |
| `openai/gpt-oss-20b` | `0.8901` | `32` |
| `meta-llama/llama-4-scout` | `0.8559` | `32` |

Head-to-head by case:

- `openai/gpt-oss-20b`: `15` wins
- `meta-llama/llama-4-scout`: `7` wins
- Ties: `10`

Result: `openai/gpt-oss-20b` remains the stronger choice on `v24` under hybrid scoring with `gpt-5.4-nano` as judge.

## Main Takeaways

- `gpt-oss-20b` kept the overall lead after moving from heuristic-only scoring to hybrid scoring.
- `llama-4-scout` still has some strengths on explicit or quasi-list formatting, but it remains less reliable on anti-hallucination and email-format discipline.
- The biggest single failure in the run was `llama-4-scout` on `ro-no-context-insertion`, where it produced a long hallucinated meta-response with invented closing text and name content instead of a clean transcript.
- `gpt-oss-20b` still has meaningful weaknesses on Romanian self-correction cases, especially `ro-self-correction` and `ro-self-correction-de-fapt`.

## Biggest `gpt-oss-20b` Wins

- `ro-no-context-insertion`
  - `gpt-oss-20b`: `0.8526`
  - `llama-4-scout`: `0.3297`
  - Llama produced a severe hallucinated email-style/meta-editing blob instead of a literal cleanup.
- `en-email-formal-confirmation`
  - `gpt-oss-20b`: `0.8549`
  - `llama-4-scout`: `0.6973`
  - Llama added `Best, [Your Name]`, which was not spoken.
- `fr-email-formal`
  - `gpt-oss-20b`: `0.7936`
  - `llama-4-scout`: `0.6465`
  - Same pattern: extra signoff hallucination.
- `en-email-recipient-name-nearmatch-body`
  - `gpt-oss-20b`: `1.0000`
  - `llama-4-scout`: `0.8547`
  - Llama appended `Best regards` even though no closing was dictated.

## Biggest `llama-4-scout` Wins

- `ro-self-correction-de-fapt`
  - `llama-4-scout`: `0.9134`
  - `gpt-oss-20b`: `0.6315`
  - Llama correctly kept only the final corrected Romanian meaning.
- `es-en-mixed-technical`
  - `llama-4-scout`: `1.0000`
  - `gpt-oss-20b`: `0.8132`
  - Llama preserved the spoken prose intent; `gpt-oss-20b` converted it into bullets.
- `en-prose-sequence-not-list`
  - `llama-4-scout`: `1.0000`
  - `gpt-oss-20b`: `0.9113`
  - Llama handled the prose sequencing punctuation slightly better.
- `en-terminal-preserve-technical-string`
  - `llama-4-scout`: `0.8975`
  - `gpt-oss-20b`: `0.8795`
  - Llama preserved the spoken leading `run` more faithfully.

## Judge Effects

- The `gpt-5.4-nano` judge generally lifted both models relative to heuristic-only scoring.
- The judge was notably more forgiving than the heuristic scorer on some formatting cases, especially:
  - prose vs list realizations
  - missing email salutation formatting
  - otherwise-clean outputs that violated a narrow formatting expectation
- Even with that softer judging, the ranking did not change: `gpt-oss-20b` still won overall and by case count.

## English-Only Subset

This run includes `19` English cases.

| Model | Avg hybrid score | English case wins |
| --- | ---: | ---: |
| `openai/gpt-oss-20b` | `0.9284` | `10` |
| `meta-llama/llama-4-scout` | `0.8887` | `3` |

English-only ties: `6`

English-only pattern:

- `gpt-oss-20b` is stronger on English email cleanup and anti-hallucination.
- `llama-4-scout` still tends to add unwanted closings such as `Best, [Your Name]` in English email-style cases.
- `llama-4-scout` has a few narrower wins on punctuation or literal phrasing, but not enough to close the overall gap.

Representative English wins for `gpt-oss-20b`:

- `en-email-formal-confirmation`
  - `gpt-oss-20b`: `0.8549`
  - `llama-4-scout`: `0.6973`
- `en-no-context-name-insertion`
  - `gpt-oss-20b`: `0.8525`
  - `llama-4-scout`: `0.7350`
- `en-email-recipient-name-nearmatch-body`
  - `gpt-oss-20b`: `1.0000`
  - `llama-4-scout`: `0.8547`
- `en-chat-keep-casual-tone`
  - `gpt-oss-20b`: `1.0000`
  - `llama-4-scout`: `0.9040`

Representative English wins for `llama-4-scout`:

- `en-prose-sequence-not-list`
  - `llama-4-scout`: `1.0000`
  - `gpt-oss-20b`: `0.9113`
- `en-terminal-preserve-technical-string`
  - `llama-4-scout`: `0.8975`
  - `gpt-oss-20b`: `0.8795`
- `en-email-recipient-name-nearmatch-greeting`
  - `llama-4-scout`: `0.9950`
  - `gpt-oss-20b`: `0.9650`

## Heuristic-Only Reference

This section records the earlier heuristic-only run from `eval/results/model-compare-v24-openrouter-2026-04-05.json` using the same models, same `v24` system prompt, and same case set, but without an LLM judge.

### Overall Heuristic Results

| Model | Avg heuristic score | Cases |
| --- | ---: | ---: |
| `openai/gpt-oss-20b` | `0.8133` | `32` |
| `meta-llama/llama-4-scout` | `0.7480` | `32` |

Heuristic head-to-head by case:

- `openai/gpt-oss-20b`: `14` wins
- `meta-llama/llama-4-scout`: `6` wins
- Ties: `12`

Heuristic-only pattern:

- `gpt-oss-20b` had a larger raw lead under heuristic scoring than under hybrid scoring.
- The heuristic scorer was harsher on formatting deviations, especially when a model produced a list instead of prose or skipped narrow email formatting expectations.
- `llama-4-scout` still showed formatting strengths on some English prose/list cases, but those were not enough to overcome its weaker anti-hallucination behavior overall.

### English-Only Heuristic Results

This run includes the same `19` English cases.

| Model | Avg heuristic score | English case wins |
| --- | ---: | ---: |
| `openai/gpt-oss-20b` | `0.8814` | `7` |
| `meta-llama/llama-4-scout` | `0.8641` | `3` |

English-only heuristic ties: `9`

Representative heuristic English wins for `gpt-oss-20b`:

- `en-cursor-rename-identifier`
  - `gpt-oss-20b`: `0.8750`
  - `llama-4-scout`: `0.6714`
- `en-chat-keep-casual-tone`
  - `gpt-oss-20b`: `1.0000`
  - `llama-4-scout`: `0.8079`
- `en-explicit-bulleted-list`
  - `gpt-oss-20b`: `0.8371`
  - `llama-4-scout`: `0.7487`

Representative heuristic English wins for `llama-4-scout`:

- `en-prose-sequence-not-list`
  - `llama-4-scout`: `1.0000`
  - `gpt-oss-20b`: `0.8210`
- `en-list-structure`
  - `llama-4-scout`: `1.0000`
  - `gpt-oss-20b`: `0.8402`
- `en-terminal-preserve-technical-string`
  - `llama-4-scout`: `0.8450`
  - `gpt-oss-20b`: `0.8239`

## Recommendation

Keep `openai/gpt-oss-20b` as the leading candidate for `v24`.

If we continue prompt work, the highest-value next step is to target `gpt-oss-20b` regressions on Romanian self-correction without weakening its stronger anti-hallucination behavior on email and no-context cases.
