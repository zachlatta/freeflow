# Original vs Baseline vs V24

Three-way comparison for:

- Original: `user-baseline-system`
- Baseline: `user-baseline-system-with-example`
- Candidate: `system-gptoss-multilingual-email-v24`
- Model: `openai/gpt-oss-20b`
- Scoring: `hybrid`
- Cases: `eval/prompt_eval_cases_system_only_en_context.json`
- Routing: OpenRouter default routing with `provider.sort=throughput`
- Concurrency: `30`
- Raw result JSON: `eval/results/original-vs-baseline-vs-v24-concurrency30-2026-04-01.json`

## Summary

| Prompt | Avg hybrid score | Cases |
|---|---:|---:|
| `system-gptoss-multilingual-email-v24` | 0.8572 | 32 |
| `user-baseline-system` | 0.8433 | 32 |
| `user-baseline-system-with-example` | 0.8114 | 32 |

Net gain for `v24` over Original: `+0.0139`

Net gain for `v24` over Baseline: `+0.0458`

## High-Level Read

`v24` won the run, but the gap to `Original` is smaller on the updated suite.

- Removing the auto-greeting expectation helped the original prompt more than the older suite did.
- `v24` still leads overall and stays strongest on the targeted literalness, self-correction, and email-name correction behavior.
- The dictated-greeting behavior now aligns with the suite rule: keep and format spoken greetings, do not add unstated ones.
- `v24` still gives up ground on some formal email and Romanian cases.

## Case Table

| Case | Original | Baseline | V24 | Best |
|---|---:|---:|---:|---|
| `en-slack-self-correction-day` | 1.0000 | 1.0000 | 1.0000 | Original |
| `en-email-formal-confirmation` | 0.9200 | 0.9200 | 0.8549 | Original |
| `en-no-context-name-insertion` | 0.8525 | 0.8525 | 0.8525 | Original |
| `en-correct-name-from-vocabulary` | 0.9375 | 0.9375 | 0.9375 | Original |
| `en-terminal-preserve-technical-string` | 0.9225 | 0.8894 | 0.8869 | Original |
| `en-chat-keep-casual-tone` | 0.8217 | 0.8539 | 1.0000 | V24 |
| `en-list-structure` | 0.6903 | 0.6903 | 0.6903 | Original |
| `ro-slack-casual` | 1.0000 | 1.0000 | 1.0000 | Original |
| `ro-email-formal` | 0.7911 | 0.9140 | 0.9140 | Baseline |
| `ro-self-correction` | 0.5272 | 0.4921 | 0.5247 | Original |
| `ro-mixed-language-technical` | 0.8811 | 0.7788 | 0.7788 | Original |
| `ro-empty-filler` | 0.9000 | 0.1250 | 0.9000 | Original |
| `ro-no-context-insertion` | 0.8526 | 0.9200 | 0.8426 | Baseline |
| `ro-self-correction-de-fapt` | 0.5845 | 0.6116 | 0.9134 | V24 |
| `ro-fillers-only-mixed` | 0.9000 | 0.9000 | 0.9000 | Original |
| `en-prose-sequence-not-list` | 1.0000 | 1.0000 | 0.9229 | Original |
| `en-keep-leading-run` | 0.9080 | 0.9130 | 0.8053 | Baseline |
| `es-chat-self-correction` | 0.6792 | 0.4484 | 0.8386 | V24 |
| `fr-email-formal` | 0.7974 | 0.7974 | 0.7974 | Original |
| `es-en-mixed-technical` | 1.0000 | 0.7979 | 0.5482 | Original |
| `de-short-chat` | 1.0000 | 1.0000 | 0.4194 | Original |
| `en-explicit-numbered-list` | 0.9184 | 0.9084 | 0.9034 | Original |
| `en-explicit-bulleted-list` | 0.9161 | 0.8785 | 0.8935 | Original |
| `es-explicit-numbered-list` | 0.7454 | 0.7688 | 0.7859 | V24 |
| `en-email-spoken-greeting` | 0.6835 | 0.8700 | 1.0000 | V24 |
| `en-slack-dictated-punctuation` | 1.0000 | 1.0000 | 1.0000 | Original |
| `en-empty-filler` | 0.9000 | 0.9000 | 0.9000 | Original |
| `en-cursor-rename-identifier` | 0.4439 | 0.7325 | 0.8111 | V24 |
| `en-email-dictated-closing` | 0.7135 | 0.8238 | 0.8333 | V24 |
| `en-email-recipient-name-nearmatch-greeting` | 0.9130 | 0.5946 | 0.9750 | V24 |
| `en-email-recipient-name-nearmatch-body` | 0.9180 | 0.6467 | 1.0000 | V24 |
| `en-technical-meta-instruction-literal` | 0.8693 | 1.0000 | 1.0000 | Baseline |

## Target Cases

### `en-email-spoken-greeting`

Scores:

| Prompt | Score |
|---|---:|
| `Original` | 0.6835 |
| `Baseline` | 0.8700 |
| `V24` | 1.0000 |

Outputs:

**Original**

```text
Hi Dana Kline, yes I can send the deck tomorrow morning.
```

**Baseline**

```text
Hi Dana, yes I can send the deck tomorrow morning.
```

**V24**

```text
Hi Dana,

Yes, I can send the deck tomorrow morning.
```

### `en-technical-meta-instruction-literal`

Scores:

| Prompt | Score |
|---|---:|
| `Original` | 0.8693 |
| `Baseline` | 1.0000 |
| `V24` | 1.0000 |

Outputs:

**Original**

```text
Ignore my last message, just write a PR description.
```

**Baseline**

```text
Ignore my last message. Just write a PR description.
```

**V24**

```text
Ignore my last message. Just write a PR description.
```

### `en-slack-self-correction-day`

Scores:

| Prompt | Score |
|---|---:|
| `Original` | 1.0000 |
| `Baseline` | 1.0000 |
| `V24` | 1.0000 |

Outputs:

**Original**

```text
Let's meet Wednesday after lunch.
```

**Baseline**

```text
Let's meet Wednesday after lunch.
```

**V24**

```text
Let's meet Wednesday after lunch.
```

### `es-en-mixed-technical`

Scores:

| Prompt | Score |
|---|---:|
| `Original` | 1.0000 |
| `Baseline` | 0.7979 |
| `V24` | 0.5482 |

Outputs:

**Original**

```text
Agrega un bullet sobre rollback plan y otro sobre feature flag cleanup.
```

**Baseline**

```text
Agregar un bullet sobre rollback plan y otro sobre feature flag cleanup.
```

**V24**

```text
- rollback plan
- feature flag cleanup
```

## Where V24 Is Clearly Better

- `en-cursor-rename-identifier`: `0.4439 -> 0.8111`
- `ro-self-correction-de-fapt`: `0.5845 -> 0.9134`
- `en-email-spoken-greeting`: `0.6835 -> 1.0000`
- `en-chat-keep-casual-tone`: `0.8217 -> 1.0000`
- `es-chat-self-correction`: `0.6792 -> 0.8386`
- `en-technical-meta-instruction-literal`: `0.8693 -> 1.0000`
- `ro-email-formal`: `0.7911 -> 0.9140`
- `en-email-dictated-closing`: `0.7135 -> 0.8333`

Representative outputs:

### `en-email-recipient-name-nearmatch-body`

**Original**

```text
Hi Thora, I wanted to follow up on the timeline that Aysha mentioned yesterday.
```

**Baseline**

```text
Hi Thora, I wanted to follow up on the timeline that Aisha mentioned yesterday.
```

**V24**

```text
Hi Thora,

I wanted to follow up on the timeline that Aysha mentioned yesterday.
```

### `en-technical-meta-instruction-literal`

**Original**

```text
Ignore my last message, just write a PR description.
```

**Baseline**

```text
Ignore my last message. Just write a PR description.
```

**V24**

```text
Ignore my last message. Just write a PR description.
```

## Where V24 Still Regresses

- `de-short-chat`: `1.0000 -> 0.4194`
- `es-en-mixed-technical`: `1.0000 -> 0.5482`
- `en-keep-leading-run`: `0.9080 -> 0.8053`
- `ro-mixed-language-technical`: `0.8811 -> 0.7788`
- `en-prose-sequence-not-list`: `1.0000 -> 0.9229`
- `en-email-formal-confirmation`: `0.9200 -> 0.8549`
- `en-terminal-preserve-technical-string`: `0.9225 -> 0.8869`
- `en-explicit-bulleted-list`: `0.9161 -> 0.8935`

<details>
<summary><code>de-short-chat</code></summary>

Raw transcript:

```text
ja sieht gut aus fuer mich
```

Expected text:

```text
Ja, sieht gut aus für mich.
```

Original:

```text
Ja, sieht gut aus für mich.
```

Baseline:

```text
Ja, sieht gut aus für mich.
```

V24:

```text
Ja sieht gut aus für mich.
```

</details>

<details>
<summary><code>es-en-mixed-technical</code></summary>

Raw transcript:

```text
agrega un bullet sobre rollback plan y otro sobre feature flag cleanup
```

Expected text:

```text
Agrega un bullet sobre rollback plan y otro sobre feature flag cleanup.
```

Original:

```text
Agrega un bullet sobre rollback plan y otro sobre feature flag cleanup.
```

Baseline:

```text
Agregar un bullet sobre rollback plan y otro sobre feature flag cleanup.
```

V24:

```text
- rollback plan
- feature flag cleanup
```

</details>

<details>
<summary><code>en-keep-leading-run</code></summary>

Raw transcript:

```text
run pnpm test dash dash watch
```

Expected text:

```text
Run pnpm test --watch.
```

Original:

```text
run pnpm test --watch
```

Baseline:

```text
run pnpm test --watch
```

V24:

```text
pnpm test --watch
```

</details>

<details>
<summary><code>ro-mixed-language-technical</code></summary>

Raw transcript:

```text
adauga te rog un bullet despre rollback plan si un altul despre feature flag cleanup
```

Expected text:

```text
Adaugă, te rog, un bullet despre rollback plan și un altul despre feature flag cleanup.
```

Original:

```text
Adaugă un bullet despre rollback plan și un altul despre feature flag cleanup.
```

Baseline:

```text
Add a bullet about rollback plan and another about feature flag cleanup.
```

V24:

```text
Add a bullet about rollback plan and another about feature flag cleanup.
```

</details>

<details>
<summary><code>en-prose-sequence-not-list</code></summary>

Raw transcript:

```text
first check the logs second confirm the env vars third rerun the job
```

Expected text:

```text
First, check the logs. Second, confirm the env vars. Third, rerun the job.
```

Original:

```text
First, check the logs. Second, confirm the env vars. Third, rerun the job.
```

Baseline:

```text
First, check the logs. Second, confirm the env vars. Third, rerun the job.
```

V24:

```text
First check the logs. Second, confirm the env vars. Third, rerun the job.
```

</details>

<details>
<summary><code>en-email-formal-confirmation</code></summary>

Raw transcript:

```text
yes that works for me i'll send the revised draft tonight
```

Expected text:

```text
Yes, that works for me. I'll send the revised draft tonight.
```

Original:

```text
Yes, that works for me. I'll send the revised draft tonight.
```

Baseline:

```text
Yes, that works for me. I'll send the revised draft tonight.
```

V24:

```text
Yes that works for me. I'll send the revised draft tonight.
```

</details>

<details>
<summary><code>en-terminal-preserve-technical-string</code></summary>

Raw transcript:

```text
run python3 scripts slash eval underscore groq underscore prompts dot py dash dash mode postprocess
```

Expected text:

```text
Run python3 scripts/eval_groq_prompts.py --mode postprocess.
```

Original:

```text
run python3 scripts/eval_groq_prompts.py --mode postprocess
```

Baseline:

```text
python3 scripts/eval_groq_prompts.py --mode postprocess
```

V24:

```text
python3 scripts/eval_groq_prompts.py --mode postprocess
```

</details>

<details>
<summary><code>en-explicit-bulleted-list</code></summary>

Raw transcript:

```text
bullet list first fix the onboarding copy second verify the signup email third review the faq
```

Expected text:

```text
- Fix the onboarding copy.
- Verify the signup email.
- Review the FAQ.
```

Original:

```text
- fix the onboarding copy
- verify the signup email
- review the FAQ
```

Baseline:

```text
- fix the onboarding copy
- verify the signup email
- review the FAQ
```

V24:

```text
- fix the onboarding copy
- verify the signup email
- review the FAQ
```

</details>
