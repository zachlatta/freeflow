#!/usr/bin/env python3
"""Evaluate FreeFlow prompt variants against OpenAI-compatible chat APIs.

This script mirrors the app's two prompt stages:
1. Context synthesis from app metadata and an optional screenshot.
2. Dictation post-processing from raw transcript + context summary.

It is intentionally standalone and uses only the Python standard library.
"""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import difflib
import json
import math
import mimetypes
import os
import re
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


APP_DEFAULT_CONTEXT_PROMPT = """You are a context synthesis assistant for a speech-to-text pipeline.
Given app/window metadata and an optional screenshot, output exactly two sentences that describe what the user is doing right now and the likely writing intent in the current window.
Prioritize concrete details only from the context: for email, identify recipients, subject or thread cues, and whether the user is replying or composing; for terminal/code/text work, identify the active command, file, document title, or topic.
If details are missing, state uncertainty instead of inventing facts.
Return only two sentences, no labels, no markdown, no extra commentary.
"""

APP_DEFAULT_SYSTEM_PROMPT = """You are a dictation post-processor. You receive raw speech-to-text output and return clean text ready to be typed into an application.

Your job:
- Remove filler words (um, uh, you know, like) unless they carry meaning.
- Fix spelling, grammar, and punctuation errors.
- When the transcript already contains a word that is a close misspelling of a name or term from the context or custom vocabulary, correct the spelling. Never insert names or terms from context that the speaker did not say.
- Preserve the speaker's intent, tone, and meaning exactly.

Output rules:
- Return ONLY the cleaned transcript text, nothing else.
- If the transcription is empty, return exactly: EMPTY
- Do not add words, names, or content that are not in the transcription. The context is only for correcting spelling of words already spoken.
- Do not change the meaning of what was said.
"""

# Verified against Groq's official Rate Limits page on 2026-03-24:
# https://console.groq.com/docs/rate-limits
DEFAULT_FREE_TEXT_MODELS = [
    "llama-3.1-8b-instant",
    "llama-3.3-70b-versatile",
    "meta-llama/llama-4-scout-17b-16e-instruct",
    "moonshotai/kimi-k2-instruct",
    "moonshotai/kimi-k2-instruct-0905",
    "openai/gpt-oss-120b",
    "openai/gpt-oss-20b",
    "qwen/qwen3-32b",
]

EMAIL_APP_NAMES = {"mail", "gmail", "outlook", "spark"}
EMAIL_SALUTATION_PATTERNS = (
    r"hi\b",
    r"hello\b",
    r"dear\b",
    r"hey\b",
    r"bonjour\b",
    r"bonsoir\b",
    r"salut\b",
    r"bună\b",
    r"buna\b",
)
EMAIL_SALUTATION_RE = re.compile(
    r"^\s*(?:" + "|".join(EMAIL_SALUTATION_PATTERNS) + r")(?:[\s,!.].*)?$",
    re.IGNORECASE,
)
EMAIL_CLOSING_RE = re.compile(
    r"^\s*(?:thanks|thank you|best|best regards|regards|cheers|mulțumesc|multumesc|merci)\b.*$",
    re.IGNORECASE,
)
OUTPUT_WRAPPER_PATTERNS = [
    re.compile(
        r"^\s*(?:here(?:'s| is)\s+(?:the\s+)?)?(?:clean(?:ed)?|corrected|polished|formatted|final)\s+"
        r"(?:transcript|text|version)\s*:?",
        re.IGNORECASE,
    ),
    re.compile(r"^\s*here(?:'s| is)\s+the\s+(?:clean|cleaned|corrected|formatted|final)\b", re.IGNORECASE),
]
LIST_NUMBER_RE = re.compile(r"^\s*\d+[.)]\s+")
LIST_BULLET_RE = re.compile(r"^\s*[-*•]\s+")
CORRECTION_MARKER_PATTERNS = (
    "no actually",
    "sorry",
    "wait",
    "or rather",
    "de fapt",
    "nu stai",
    "ba nu",
    "perdón",
    "perdon",
    "non",
)
GREETING_STOP_WORDS = {
    "comma",
    "yes",
    "yeah",
    "yep",
    "i",
    "ill",
    "i'll",
    "thank",
    "thanks",
    "please",
    "can",
    "could",
    "we",
    "that",
    "this",
}
GENERIC_CAPITALIZED_WORDS = {
    "The",
    "This",
    "That",
    "These",
    "Those",
    "Mail",
    "Slack",
    "Superhuman",
    "LinkedIn",
    "Launch",
    "Budget",
    "Intro",
    "Re",
    "Hi",
    "Hello",
    "Dear",
}
WORD_RE = re.compile(r"[A-Za-zÀ-ÿ']+")
CAPITALIZED_NAME_RE = re.compile(r"\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b")


@dataclass
class Variant:
    name: str
    prompt: str


@dataclass
class Case:
    id: str
    metadata: dict[str, str]
    raw_transcript: str
    custom_vocabulary: list[str]
    expected_output: str | None
    expected_context_summary: str | None
    required_context_terms: list[str]
    forbidden_context_terms: list[str]
    required_output_terms: list[str]
    forbidden_output_terms: list[str]
    screenshot_path: str | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", default="eval/prompt_eval_cases.json", help="Path to evaluation cases JSON.")
    parser.add_argument(
        "--prompts",
        default="eval/prompt_variants.json",
        help="Path to prompt variants JSON.",
    )
    parser.add_argument(
        "--mode",
        choices=("context", "postprocess", "pipeline"),
        default="pipeline",
        help="Which stage to evaluate.",
    )
    parser.add_argument(
        "--models",
        nargs="+",
        default=DEFAULT_FREE_TEXT_MODELS,
        help="Models to evaluate. Defaults to a Groq free-tier shortlist used during this search.",
    )
    parser.add_argument(
        "--context-variants",
        nargs="*",
        default=None,
        help="Optional subset of context variant names.",
    )
    parser.add_argument(
        "--system-variants",
        nargs="*",
        default=None,
        help="Optional subset of system variant names.",
    )
    parser.add_argument(
        "--base-url",
        default=(
            os.environ.get("LLM_BASE_URL")
            or os.environ.get("OPENAI_BASE_URL")
            or os.environ.get("GROQ_BASE_URL")
            or "https://api.groq.com/openai/v1"
        ),
        help="OpenAI-compatible base URL. Supports Groq directly or OpenRouter.",
    )
    parser.add_argument(
        "--api-key",
        default=(
            os.environ.get("LLM_API_KEY")
            or os.environ.get("OPENROUTER_API_KEY")
            or os.environ.get("OPENAI_API_KEY")
            or os.environ.get("GROQ_API_KEY")
            or ""
        ),
        help="API key for the selected base URL. Checks LLM_API_KEY, OPENROUTER_API_KEY, OPENAI_API_KEY, then GROQ_API_KEY.",
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=0.0,
        help="Sampling temperature for post-processing. Context uses max(temperature, 0.2) to mirror the app.",
    )
    parser.add_argument(
        "--max-context-cases",
        type=int,
        default=None,
        help="Optional limit on context cases.",
    )
    parser.add_argument(
        "--max-postprocess-cases",
        type=int,
        default=None,
        help="Optional limit on post-process cases.",
    )
    parser.add_argument(
        "--min-request-interval",
        type=float,
        default=2.2,
        help="Minimum seconds between API calls to stay under common RPM limits.",
    )
    parser.add_argument(
        "--max-retries",
        type=int,
        default=4,
        help="Retries for transient API failures and 429s.",
    )
    parser.add_argument(
        "--max-concurrency",
        type=int,
        default=32,
        help="Number of cases to evaluate in parallel. Use with care against provider rate limits.",
    )
    parser.add_argument(
        "--output-json",
        default=None,
        help="Optional path to write the full results payload.",
    )
    parser.add_argument(
        "--provider-order",
        nargs="*",
        default=None,
        help="Optional OpenRouter provider order to prioritize. By default, no provider is forced.",
    )
    parser.add_argument(
        "--provider-sort",
        choices=("throughput", "latency", "price"),
        default=None,
        help="Optional OpenRouter provider sort. Defaults to throughput on OpenRouter, which is equivalent to Nitro routing.",
    )
    parser.add_argument(
        "--allow-provider-fallbacks",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="Whether to allow provider fallbacks when provider routing is requested. Defaults to enabled unless explicitly disabled.",
    )
    parser.add_argument(
        "--scoring-mode",
        choices=("heuristic", "llm", "hybrid"),
        default="heuristic",
        help="How to score outputs. 'llm' uses the judge model when provided, otherwise the candidate model; 'hybrid' averages heuristic and llm scores.",
    )
    parser.add_argument(
        "--judge-model",
        default=None,
        help="Optional separate model to use for LLM judging. Defaults to the candidate model when omitted.",
    )
    return parser.parse_args()


def load_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def load_variants(path: str) -> tuple[list[Variant], list[Variant]]:
    payload = load_json(path)
    context_variants = [
        Variant(name=item["name"], prompt=item["prompt"])
        for item in payload.get("context_variants", [])
    ]
    system_variants = [
        Variant(name=item["name"], prompt=item["prompt"])
        for item in payload.get("system_variants", [])
    ]

    if not context_variants:
        context_variants = [Variant(name="app-default-context", prompt=APP_DEFAULT_CONTEXT_PROMPT)]
    if not system_variants:
        system_variants = [Variant(name="app-default-system", prompt=APP_DEFAULT_SYSTEM_PROMPT)]

    return context_variants, system_variants


def load_cases(path: str) -> list[Case]:
    payload = load_json(path)
    cases = []
    for item in payload.get("cases", []):
        cases.append(
            Case(
                id=item["id"],
                metadata=item.get("metadata", {}),
                raw_transcript=item.get("raw_transcript", ""),
                custom_vocabulary=item.get("custom_vocabulary", []),
                expected_output=item.get("expected_output"),
                expected_context_summary=item.get("expected_context_summary"),
                required_context_terms=item.get("required_context_terms", []),
                forbidden_context_terms=item.get("forbidden_context_terms", []),
                required_output_terms=item.get("required_output_terms", []),
                forbidden_output_terms=item.get("forbidden_output_terms", []),
                screenshot_path=item.get("screenshot_path"),
            )
        )
    return cases


def normalize_text(value: str) -> str:
    lowered = value.strip().lower()
    lowered = re.sub(r"\s+", " ", lowered)
    return lowered


def similarity_score(left: str, right: str) -> float:
    return difflib.SequenceMatcher(None, normalize_text(left), normalize_text(right)).ratio()


def contains_term(text: str, term: str) -> bool:
    return normalize_text(term) in normalize_text(text)


def term_score(text: str, required: list[str], forbidden: list[str]) -> float:
    required_score = 1.0
    if required:
        hits = sum(1 for term in required if contains_term(text, term))
        required_score = hits / len(required)

    forbidden_penalty = 0.0
    if forbidden:
        misses = sum(1 for term in forbidden if contains_term(text, term))
        forbidden_penalty = misses / len(forbidden)

    return max(0.0, required_score - forbidden_penalty)


def is_email_case(case: Case) -> bool:
    app_name = normalize_text(case.metadata.get("app_name", ""))
    if app_name in EMAIL_APP_NAMES:
        return True
    bundle_id = normalize_text(case.metadata.get("bundle_identifier", ""))
    if any(name in bundle_id for name in EMAIL_APP_NAMES):
        return True
    window_title = normalize_text(case.metadata.get("window_title", ""))
    return window_title.startswith("re:")


def email_format_score(output: str, case: Case) -> float:
    if not is_email_case(case):
        return 1.0

    stripped = output.strip()
    if not stripped:
        return 0.0

    lines = [line.strip() for line in stripped.splitlines() if line.strip()]
    if not lines:
        return 0.0

    has_salutation = bool(EMAIL_SALUTATION_RE.match(lines[0]))
    has_newline = len(lines) >= 2
    has_blank_line = bool(re.search(r"\n\s*\n", stripped))
    closing_score = 1.0
    expected_lines = [line.strip() for line in (case.expected_output or "").splitlines() if line.strip()]
    expected_has_closing = bool(expected_lines and EMAIL_CLOSING_RE.match(expected_lines[-1]))
    if expected_has_closing:
        actual_has_closing_line = bool(lines and EMAIL_CLOSING_RE.match(lines[-1]))
        closing_blank_line = bool(re.search(r"\n\s*\n\s*" + re.escape(lines[-1]) + r"\s*$", stripped)) if actual_has_closing_line else False
        closing_score = (0.7 * float(actual_has_closing_line)) + (0.3 * float(closing_blank_line))
    base_score = (0.6 * float(has_salutation)) + (0.25 * float(has_newline)) + (0.15 * float(has_blank_line))
    return (0.8 * base_score) + (0.2 * closing_score)


def output_contract_score(output: str) -> float:
    stripped = output.strip()
    if not stripped:
        return 1.0
    for pattern in OUTPUT_WRAPPER_PATTERNS:
        if pattern.search(stripped):
            return 0.0
    return 1.0


def explicit_numbered_list_expected(case: Case) -> bool:
    if not case.expected_output:
        return False
    lines = [line.strip() for line in case.expected_output.splitlines() if line.strip()]
    return len(lines) >= 2 and all(LIST_NUMBER_RE.match(line) for line in lines)


def explicit_bulleted_list_expected(case: Case) -> bool:
    if not case.expected_output:
        return False
    lines = [line.strip() for line in case.expected_output.splitlines() if line.strip()]
    return len(lines) >= 2 and all(LIST_BULLET_RE.match(line) for line in lines)


def prose_not_list_expected(case: Case) -> bool:
    if not case.expected_output:
        return False
    if "\n" in case.expected_output:
        return False
    markers = {"1.", "2.", "3.", "1)", "-"}
    return any(term in markers for term in case.forbidden_output_terms)


def structure_format_score(output: str, case: Case) -> float | None:
    stripped = output.strip()
    if not stripped:
        return 0.0

    lines = [line.rstrip() for line in stripped.splitlines() if line.strip()]
    if explicit_numbered_list_expected(case):
        if len(lines) < 2:
            return 0.0
        matches = sum(1 for line in lines if LIST_NUMBER_RE.match(line))
        return matches / len(lines)

    if explicit_bulleted_list_expected(case):
        if len(lines) < 2:
            return 0.0
        matches = sum(1 for line in lines if LIST_BULLET_RE.match(line))
        return matches / len(lines)

    if prose_not_list_expected(case):
        if any(LIST_NUMBER_RE.match(line) or LIST_BULLET_RE.match(line) for line in lines):
            return 0.0
        return 1.0

    return None


def correction_cleanup_score(output: str, case: Case) -> float | None:
    transcript = normalize_text(case.raw_transcript)
    if not any(marker in transcript for marker in CORRECTION_MARKER_PATTERNS):
        return None

    normalized_output = normalize_text(output)
    lingering_markers = sum(1 for marker in CORRECTION_MARKER_PATTERNS if marker in normalized_output)
    marker_score = 1.0 - min(1.0, lingering_markers / 2)

    forbidden_hits = 0
    if case.forbidden_output_terms:
        forbidden_hits = sum(1 for term in case.forbidden_output_terms if contains_term(output, term))
    forbidden_score = 1.0 - min(1.0, forbidden_hits / max(1, len(case.forbidden_output_terms)))

    return max(0.0, (0.45 * marker_score) + (0.55 * forbidden_score))


def combined_format_score(output: str, case: Case) -> float:
    components: list[float] = []
    if is_email_case(case):
        components.append(email_format_score(output, case))
    structure_score = structure_format_score(output, case)
    if structure_score is not None:
        components.append(structure_score)
    correction_score = correction_cleanup_score(output, case)
    if correction_score is not None:
        components.append(correction_score)
    if not components:
        return 1.0
    return sum(components) / len(components)


def score_context(summary: str, case: Case) -> dict[str, float]:
    term_component = term_score(summary, case.required_context_terms, case.forbidden_context_terms)
    reference_component = (
        similarity_score(summary, case.expected_context_summary)
        if case.expected_context_summary
        else term_component
    )
    total = (0.55 * term_component) + (0.45 * reference_component)
    return {
        "context_total": round(total, 4),
        "context_terms": round(term_component, 4),
        "context_reference": round(reference_component, 4),
    }


def score_output(output: str, case: Case) -> dict[str, float]:
    term_component = term_score(output, case.required_output_terms, case.forbidden_output_terms)
    if case.expected_output is not None:
        reference_component = similarity_score(output, case.expected_output)
        exact_component = 1.0 if normalize_text(output) == normalize_text(case.expected_output) else 0.0
    else:
        reference_component = term_component
        exact_component = 0.0

    format_component = combined_format_score(output, case)
    contract_component = output_contract_score(output)
    base_total = (0.6 * reference_component) + (0.25 * term_component) + (0.15 * exact_component)
    total = base_total * (0.65 + (0.20 * format_component) + (0.15 * contract_component))
    return {
        "output_total": round(total, 4),
        "output_base": round(base_total, 4),
        "output_terms": round(term_component, 4),
        "output_reference": round(reference_component, 4),
        "output_exact": round(exact_component, 4),
        "output_format": round(format_component, 4),
        "output_contract": round(contract_component, 4),
    }


def extract_json_object(value: str) -> dict[str, Any]:
    def try_parse(candidate: str) -> dict[str, Any] | None:
        try:
            parsed = json.loads(candidate)
        except json.JSONDecodeError:
            return None
        return parsed if isinstance(parsed, dict) else None

    direct = try_parse(value.strip())
    if direct is not None:
        return direct

    fenced_match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", value, re.DOTALL)
    if fenced_match:
        fenced = try_parse(fenced_match.group(1))
        if fenced is not None:
            return fenced

    # Try every balanced {...} span and return the first valid JSON object.
    starts: list[int] = []
    for index, char in enumerate(value):
        if char == "{":
            starts.append(index)
        elif char == "}":
            for start in reversed(starts):
                candidate = try_parse(value[start:index + 1])
                if candidate is not None:
                    return candidate

    # Fallback: extract the expected judge fields from malformed pseudo-JSON.
    field_patterns = {
        "meaning_preservation": r'"meaning_preservation"\s*:\s*([0-9.]+)',
        "cleanup_quality": r'"cleanup_quality"\s*:\s*([0-9.]+)',
        "correction_quality": r'"correction_quality"\s*:\s*([0-9.]+)',
        "format_fit": r'"format_fit"\s*:\s*([0-9.]+)',
        "anti_hallucination": r'"anti_hallucination"\s*:\s*([0-9.]+)',
        "romanian_or_language_preservation": r'"romanian_or_language_preservation"\s*:\s*([0-9.]+)',
        "output_contract": r'"output_contract"\s*:\s*([0-9.]+)',
        "overall": r'"overall"\s*:\s*([0-9.]+)',
    }
    extracted: dict[str, Any] = {}
    for key, pattern in field_patterns.items():
        match = re.search(pattern, value)
        if match:
            extracted[key] = match.group(1)

    verdict_match = re.search(r'"verdict"\s*:\s*"(.*?)"', value, re.DOTALL)
    if verdict_match:
        extracted["verdict"] = verdict_match.group(1)

    if extracted:
        return extracted

    raise ValueError("No JSON object found in judge response")


def clamp_score(value: Any) -> float:
    try:
        score = float(value)
    except (TypeError, ValueError):
        return 0.0
    if math.isnan(score) or math.isinf(score):
        return 0.0
    return max(0.0, min(1.0, score))


def score_with_llm_judge(
    client: "ChatApiClient",
    judge_model: str,
    case: Case,
    context_summary: str,
    output_text: str,
) -> dict[str, Any]:
    rubric = {
        "meaning_preservation": "Did the output preserve the speaker's final intended meaning exactly?",
        "cleanup_quality": "Did it remove filler, false starts, and transcription artifacts appropriately?",
        "correction_quality": "Did it correctly fix spelling or close misspellings without inventing terms?",
        "format_fit": "Does formatting fit the destination context described in the context summary?",
        "anti_hallucination": "Did it avoid adding names, facts, or details not present in the transcript?",
        "romanian_or_language_preservation": "Did it preserve the intended language, including Romanian or mixed-language text, correctly?",
        "output_contract": "Did it return only the final cleaned text, with no explanation, labels, or extra commentary?",
    }
    system_prompt = """You are grading a dictation post-processing result.
Return strict JSON only.

    Score each category from 0 to 1:
    - meaning_preservation
    - cleanup_quality
    - correction_quality
    - format_fit
    - anti_hallucination
    - romanian_or_language_preservation
    - output_contract

    Then return:
    - overall: weighted average from 0 to 1
    - verdict: one short sentence

    Weights:
    - meaning_preservation: 0.25
    - cleanup_quality: 0.10
    - correction_quality: 0.15
    - format_fit: 0.10
    - anti_hallucination: 0.15
    - romanian_or_language_preservation: 0.10
    - output_contract: 0.15

    Use the expected output as the gold reference, but allow small punctuation differences when meaning and formatting remain correct.
    For email cases, proper formatting includes a salutation on the first line and newline-separated body paragraphs.
    If the raw transcript contains a self-correction, the candidate must keep only the final corrected meaning. Leaving the abandoned version in the output should score meaning_preservation and cleanup_quality low.
    If the transcript explicitly asks for a numbered or bulleted list, prose sentences should score format_fit low. If the expected output is prose, converting it into a list should also score format_fit low.
    If the transcript is filler-only and the expected output is empty, any non-empty candidate should score cleanup_quality, meaning_preservation, and output_contract low.
    If the candidate adds any explanation, surrounding quotes, labels, boilerplate like "Here is the clean transcript", or extra sentences that were not dictated, score output_contract very low and reduce overall accordingly."""
    user_prompt = json.dumps(
        {
            "rubric": rubric,
            "case_id": case.id,
            "context_summary": context_summary,
            "raw_transcript": case.raw_transcript,
            "custom_vocabulary": case.custom_vocabulary,
            "expected_output": case.expected_output,
            "candidate_output": output_text,
        },
        ensure_ascii=False,
        indent=2,
    )
    response = client.chat(
        model=judge_model,
        system_prompt=system_prompt,
        user_content=user_prompt,
        temperature=0.0,
    )
    try:
        parsed = extract_json_object(response)
    except ValueError:
        return {
            "llm_meaning_preservation": 0.0,
            "llm_cleanup_quality": 0.0,
            "llm_correction_quality": 0.0,
            "llm_format_fit": 0.0,
            "llm_anti_hallucination": 0.0,
            "llm_language_preservation": 0.0,
            "llm_output_contract": 0.0,
            "llm_output_total": 0.0,
            "llm_verdict": f"Judge parse failure: {response[:200].strip()}",
            "llm_raw_response": response,
        }
    llm_scores = {
        "llm_meaning_preservation": clamp_score(parsed.get("meaning_preservation")),
        "llm_cleanup_quality": clamp_score(parsed.get("cleanup_quality")),
        "llm_correction_quality": clamp_score(parsed.get("correction_quality")),
        "llm_format_fit": clamp_score(parsed.get("format_fit")),
        "llm_anti_hallucination": clamp_score(parsed.get("anti_hallucination")),
        "llm_language_preservation": clamp_score(parsed.get("romanian_or_language_preservation")),
        "llm_output_contract": clamp_score(parsed.get("output_contract")),
    }
    llm_total = (
        0.25 * llm_scores["llm_meaning_preservation"]
        + 0.10 * llm_scores["llm_cleanup_quality"]
        + 0.15 * llm_scores["llm_correction_quality"]
        + 0.10 * llm_scores["llm_format_fit"]
        + 0.15 * llm_scores["llm_anti_hallucination"]
        + 0.10 * llm_scores["llm_language_preservation"]
        + 0.15 * llm_scores["llm_output_contract"]
    )
    llm_scores["llm_output_total"] = llm_total
    for key, value in list(llm_scores.items()):
        if isinstance(value, (int, float)):
            llm_scores[key] = round(value, 4)
    llm_scores["llm_verdict"] = str(parsed.get("verdict", "")).strip()
    llm_scores["llm_raw_response"] = response
    return llm_scores


def merge_output_scores(
    heuristic_scores: dict[str, float],
    llm_scores: dict[str, float] | None,
    scoring_mode: str,
) -> dict[str, float | str]:
    if scoring_mode == "heuristic" or llm_scores is None:
        return heuristic_scores
    if scoring_mode == "llm":
        return {
            **heuristic_scores,
            **llm_scores,
            "output_total": llm_scores["llm_output_total"],
        }
    hybrid_total = round((heuristic_scores["output_total"] + llm_scores["llm_output_total"]) / 2, 4)
    return {
        **heuristic_scores,
        **llm_scores,
        "output_total": hybrid_total,
    }


def build_metadata_block(metadata: dict[str, str]) -> str:
    return "\n".join(
        [
            f"App: {metadata.get('app_name', 'Unknown')}",
            f"Bundle ID: {metadata.get('bundle_identifier', 'Unknown')}",
            f"Window: {metadata.get('window_title', 'Unknown')}",
            f"Selected text: {metadata.get('selected_text', 'None')}",
        ]
    )


def build_context_user_message(case: Case, include_screenshot: bool) -> tuple[Any, str]:
    metadata = build_metadata_block(case.metadata)
    text_only_prompt = f"Analyze the context and infer the user's current activity in exactly two sentences.\n\n{metadata}"
    if include_screenshot and case.screenshot_path:
        screenshot_data_uri = image_path_to_data_uri(case.screenshot_path)
        description = "[screenshot attached]\nAnalyze the screenshot plus metadata to infer current activity.\n" + metadata
        content: Any = [
            {"type": "text", "text": "Analyze the screenshot plus metadata to infer current activity."},
            {"type": "text", "text": metadata},
            {"type": "image_url", "image_url": {"url": screenshot_data_uri}},
        ]
        return content, description
    return text_only_prompt, text_only_prompt


def build_postprocess_user_message(context_summary: str, raw_transcript: str, custom_vocabulary: list[str]) -> str:
    normalized_vocabulary = ", ".join(term.strip() for term in custom_vocabulary if term.strip())
    return f"""Clean and format the following dictation for the destination app described in the context.

CONTEXT:
{context_summary}

CUSTOM VOCABULARY (spelling reference only):
{normalized_vocabulary}

RAW TRANSCRIPT:
{raw_transcript}

Return only the final text. If the transcript is empty or contains only filler, return exactly: EMPTY
"""


def merged_system_prompt(base_prompt: str, custom_vocabulary: list[str]) -> str:
    normalized_vocabulary = ", ".join(term.strip() for term in custom_vocabulary if term.strip())
    if not normalized_vocabulary:
        return base_prompt
    return (
        base_prompt.strip()
        + "\n\nThe following vocabulary must be treated as high-priority terms while rewriting.\n"
        + "Use these spellings exactly in the output when relevant:\n"
        + normalized_vocabulary
    )


def image_path_to_data_uri(path: str) -> str:
    file_path = Path(path)
    mime_type, _ = mimetypes.guess_type(file_path.name)
    if not mime_type:
        mime_type = "image/png"
    raw = file_path.read_bytes()
    encoded = base64.b64encode(raw).decode("ascii")
    return f"data:{mime_type};base64,{encoded}"


class ChatApiClient:
    def __init__(
        self,
        api_key: str,
        base_url: str,
        min_request_interval: float,
        max_retries: int,
        provider_order: list[str] | None = None,
        provider_sort: str | None = None,
        allow_provider_fallbacks: bool = True,
    ) -> None:
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.min_request_interval = min_request_interval
        self.max_retries = max_retries
        self.last_request_monotonic = 0.0
        self.provider_order = provider_order or []
        self.provider_sort = provider_sort
        self.allow_provider_fallbacks = allow_provider_fallbacks

    def chat(self, *, model: str, system_prompt: str, user_content: Any, temperature: float) -> str:
        self._respect_min_interval()
        payload = {
            "model": model,
            "temperature": temperature,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_content},
            ],
        }
        if "openrouter.ai" in self.base_url:
            provider: dict[str, Any] = {}
            if self.provider_order:
                provider["order"] = self.provider_order
                provider["allow_fallbacks"] = self.allow_provider_fallbacks
            if self.provider_sort:
                provider["sort"] = self.provider_sort
            if provider:
                payload["provider"] = provider
        request = urllib.request.Request(
            url=f"{self.base_url}/chat/completions",
            data=json.dumps(payload).encode("utf-8"),
            headers=self._headers(),
            method="POST",
        )

        attempt = 0
        while True:
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    self.last_request_monotonic = time.monotonic()
                    body = json.loads(response.read().decode("utf-8"))
                    message = body["choices"][0]["message"]
                    content = message.get("content")
                    if isinstance(content, str):
                        return content.strip()
                    if isinstance(content, list):
                        text_parts = []
                        for item in content:
                            if isinstance(item, dict) and item.get("type") == "text":
                                text_parts.append(str(item.get("text", "")))
                        return "".join(text_parts).strip()
                    return ""
            except urllib.error.HTTPError as exc:
                attempt += 1
                details = exc.read().decode("utf-8", errors="replace")
                if attempt > self.max_retries:
                    raise RuntimeError(f"Chat API error {exc.code}: {details}") from exc

                retry_after = exc.headers.get("retry-after")
                if exc.code == 429 and retry_after:
                    time.sleep(float(retry_after) + 0.25)
                    continue

                if exc.code == 429:
                    try:
                        parsed_details = json.loads(details)
                    except json.JSONDecodeError:
                        parsed_details = {}
                    retry_after_seconds = (
                        parsed_details.get("error", {})
                        .get("metadata", {})
                        .get("retry_after_seconds")
                    )
                    if retry_after_seconds is not None:
                        time.sleep(float(retry_after_seconds) + 0.25)
                        continue

                if exc.code in {408, 409, 429, 500, 502, 503, 504}:
                    time.sleep(min(12.0, 1.5 * attempt))
                    continue

                raise RuntimeError(f"Chat API error {exc.code}: {details}") from exc
            except urllib.error.URLError as exc:
                attempt += 1
                if attempt > self.max_retries:
                    raise RuntimeError(f"Chat API network error: {exc}") from exc
                time.sleep(min(12.0, 1.5 * attempt))
            except TimeoutError as exc:
                attempt += 1
                if attempt > self.max_retries:
                    raise RuntimeError(f"Chat API read timeout: {exc}") from exc
                time.sleep(min(12.0, 1.5 * attempt))

    def _respect_min_interval(self) -> None:
        now = time.monotonic()
        elapsed = now - self.last_request_monotonic
        if elapsed < self.min_request_interval:
            time.sleep(self.min_request_interval - elapsed)

    def _headers(self) -> dict[str, str]:
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
            "User-Agent": "freeflow-prompt-eval/1.0",
        }
        if "openrouter.ai" in self.base_url:
            headers["HTTP-Referer"] = "https://github.com/zachlatta/freeflow"
            headers["X-Title"] = "FreeFlow Prompt Eval"
        return headers


def filter_variants(variants: list[Variant], requested_names: list[str] | None) -> list[Variant]:
    if not requested_names:
        return variants
    requested = set(requested_names)
    filtered = [variant for variant in variants if variant.name in requested]
    if not filtered:
        raise SystemExit(f"No variants matched: {', '.join(requested_names)}")
    return filtered


def sanitize_postprocessed_transcript(value: str) -> str:
    result = value.strip()
    if result.startswith('"') and result.endswith('"') and len(result) > 1:
        result = result[1:-1].strip()
    return "" if result == "EMPTY" else result


def extract_first_name_candidates(case: Case, context_summary: str) -> list[str]:
    candidates: list[str] = []
    sources = [context_summary, case.metadata.get("window_title", ""), *case.custom_vocabulary]
    seen: set[str] = set()
    for source in sources:
        for match in CAPITALIZED_NAME_RE.findall(source):
            if match in GENERIC_CAPITALIZED_WORDS:
                continue
            first = match.split()[0]
            if len(first) < 3 or first in GENERIC_CAPITALIZED_WORDS:
                continue
            if first not in seen:
                seen.add(first)
                candidates.append(first)
    return candidates


def build_name_correction_map(case: Case, context_summary: str) -> dict[str, str]:
    candidates = extract_first_name_candidates(case, context_summary)
    transcript_tokens = {token.lower() for token in WORD_RE.findall(case.raw_transcript) if len(token) >= 3}
    mapping: dict[str, str] = {}
    for token in transcript_tokens:
        best_candidate = ""
        best_score = 0.0
        for candidate in candidates:
            score = similarity_score(token, candidate)
            same_initial = token[:1] == candidate[:1].lower()
            if score > best_score and (same_initial or score >= 0.9):
                best_candidate = candidate
                best_score = score
        if best_candidate and best_score >= 0.72 and token != best_candidate.lower():
            mapping[token] = best_candidate
    return mapping


def apply_name_corrections(text: str, correction_map: dict[str, str]) -> str:
    if not correction_map:
        return text

    pattern = re.compile(
        r"\b(" + "|".join(re.escape(token) for token in sorted(correction_map, key=len, reverse=True)) + r")\b",
        re.IGNORECASE,
    )

    def replace(match: re.Match[str]) -> str:
        token = match.group(0)
        return correction_map.get(token.lower(), token)

    return pattern.sub(replace, text)


def extract_spoken_greeting_name_tokens(raw_transcript: str) -> tuple[str, list[str]] | None:
    tokens = WORD_RE.findall(raw_transcript)
    if not tokens:
        return None
    salutation = tokens[0].lower()
    if salutation not in {"hi", "hello", "hey", "dear", "bonjour", "bonsoir", "salut", "bună", "buna"}:
        return None
    name_tokens: list[str] = []
    for token in tokens[1:]:
        lowered = token.lower()
        if lowered in GREETING_STOP_WORDS:
            break
        name_tokens.append(token)
        if len(name_tokens) >= 3:
            break
    return salutation, name_tokens


def preserve_spoken_email_greeting_scope(output: str, case: Case, context_summary: str) -> str:
    if not is_email_case(case):
        return output

    correction_map = build_name_correction_map(case, context_summary)
    corrected_output = apply_name_corrections(output, correction_map)
    spoken_greeting = extract_spoken_greeting_name_tokens(case.raw_transcript)
    stripped = corrected_output.lstrip()

    if spoken_greeting is None:
        if not EMAIL_SALUTATION_RE.match(stripped.splitlines()[0].strip()) if stripped.splitlines() else False:
            return corrected_output
        return re.sub(r"^\s*[^\n]+\n\s*\n?", "", corrected_output, count=1).lstrip()

    salutation, spoken_name_tokens = spoken_greeting
    lines = corrected_output.splitlines()
    first_nonempty = next((idx for idx, line in enumerate(lines) if line.strip()), None)
    if first_nonempty is None:
        return corrected_output
    if not EMAIL_SALUTATION_RE.match(lines[first_nonempty].strip()):
        return corrected_output

    normalized_salutation = salutation.capitalize()
    corrected_name_tokens = [correction_map.get(token.lower(), token.capitalize()) for token in spoken_name_tokens]
    greeting_line = normalized_salutation
    if corrected_name_tokens:
        greeting_line += " " + " ".join(corrected_name_tokens)
    if not greeting_line.endswith(","):
        greeting_line += ","
    lines[first_nonempty] = greeting_line
    return "\n".join(lines)


def run_context_stage(client: ChatApiClient, model: str, variant: Variant, case: Case, temperature: float) -> tuple[str, dict[str, float]]:
    user_content, _ = build_context_user_message(case, include_screenshot=bool(case.screenshot_path))
    summary = client.chat(
        model=model,
        system_prompt=variant.prompt,
        user_content=user_content,
        temperature=max(temperature, 0.2),
    )
    summary = summary.strip()
    return summary, score_context(summary, case)


def run_postprocess_stage(
    client: ChatApiClient,
    model: str,
    variant: Variant,
    case: Case,
    context_summary: str,
    temperature: float,
) -> tuple[str, dict[str, float]]:
    output = client.chat(
        model=model,
        system_prompt=merged_system_prompt(variant.prompt, case.custom_vocabulary),
        user_content=build_postprocess_user_message(context_summary, case.raw_transcript, case.custom_vocabulary),
        temperature=temperature,
    )
    cleaned = sanitize_postprocessed_transcript(output)
    if variant.name in {"system-gptoss-multilingual-email-v23", "system-gptoss-multilingual-email-v24"}:
        cleaned = preserve_spoken_email_greeting_scope(cleaned, case, context_summary)
    return cleaned, score_output(cleaned, case)


def print_progress(message: str) -> None:
    print(message, file=sys.stderr)


def build_result_entry(
    *,
    model: str,
    context_variant: str,
    system_variant: str,
    case_id: str,
    context_summary: str | None,
    output_text: str | None,
    scores: dict[str, Any],
) -> dict[str, Any]:
    total_score = round(float(scores.get("context_total", 0.0)) + float(scores.get("output_total", 0.0)), 4)
    return {
        "model": model,
        "context_variant": context_variant,
        "system_variant": system_variant,
        "case_id": case_id,
        "context_summary": context_summary,
        "output_text": output_text,
        "scores": scores,
        "combined_total": total_score,
    }


def summarize(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[tuple[str, str, str], list[float]] = {}
    for entry in entries:
        key = (entry["model"], entry["context_variant"], entry["system_variant"])
        grouped.setdefault(key, []).append(entry["combined_total"])

    summary = []
    for (model, context_variant, system_variant), scores in grouped.items():
        summary.append(
            {
                "model": model,
                "context_variant": context_variant,
                "system_variant": system_variant,
                "avg_combined_total": round(sum(scores) / len(scores), 4),
                "cases": len(scores),
            }
        )

    summary.sort(key=lambda item: item["avg_combined_total"], reverse=True)
    return summary


def evaluate_case(
    *,
    client: ChatApiClient,
    model: str,
    case: Case,
    args: argparse.Namespace,
    context_variants: list[Variant],
    system_variants: list[Variant],
) -> list[dict[str, Any]]:
    case_results: list[dict[str, Any]] = []
    active_context_variants = context_variants if args.mode in {"context", "pipeline"} else [Variant(name="-", prompt="")]
    judge_model = args.judge_model or model

    for context_variant in active_context_variants:
        context_summary = case.expected_context_summary or ""
        context_scores: dict[str, float] = {}
        if args.mode in {"context", "pipeline"}:
            print_progress(f"[context] model={model} case={case.id} variant={context_variant.name}")
            context_summary, context_scores = run_context_stage(
                client=client,
                model=model,
                variant=context_variant,
                case=case,
                temperature=args.temperature,
            )

        if args.mode == "context":
            case_results.append(
                build_result_entry(
                    model=model,
                    context_variant=context_variant.name,
                    system_variant="-",
                    case_id=case.id,
                    context_summary=context_summary,
                    output_text=None,
                    scores=context_scores,
                )
            )
            continue

        selected_system_variants = system_variants
        context_variant_name = "-" if args.mode == "postprocess" else context_variant.name

        for system_variant in selected_system_variants:
            print_progress(
                f"[postprocess] model={model} case={case.id} context={context_variant_name} system={system_variant.name}"
            )
            output_text, output_scores = run_postprocess_stage(
                client=client,
                model=model,
                variant=system_variant,
                case=case,
                context_summary=context_summary,
                temperature=args.temperature,
            )
            llm_scores = None
            if args.scoring_mode in {"llm", "hybrid"}:
                print_progress(
                    f"[judge] model={model} judge={judge_model} case={case.id} system={system_variant.name} scoring={args.scoring_mode}"
                )
                llm_scores = score_with_llm_judge(
                    client=client,
                    judge_model=judge_model,
                    case=case,
                    context_summary=context_summary,
                    output_text=output_text,
                )
            scores = {}
            scores.update(context_scores)
            scores.update(merge_output_scores(output_scores, llm_scores, args.scoring_mode))
            case_results.append(
                build_result_entry(
                    model=model,
                    context_variant=context_variant_name,
                    system_variant=system_variant.name,
                    case_id=case.id,
                    context_summary=context_summary if args.mode == "pipeline" else None,
                    output_text=output_text,
                    scores=scores,
                )
            )

    return case_results


def main() -> int:
    args = parse_args()
    if not args.api_key.strip():
        raise SystemExit(
            "Missing API key. Set LLM_API_KEY, OPENROUTER_API_KEY, OPENAI_API_KEY, or GROQ_API_KEY, or pass --api-key."
        )
    if "openrouter.ai" in args.base_url and args.provider_sort is None:
        args.provider_sort = "throughput"
    if args.allow_provider_fallbacks is None:
        args.allow_provider_fallbacks = True

    context_variants, system_variants = load_variants(args.prompts)
    context_variants = filter_variants(context_variants, args.context_variants)
    system_variants = filter_variants(system_variants, args.system_variants)
    cases = load_cases(args.cases)
    if not cases:
        raise SystemExit("No evaluation cases found.")
    if args.mode == "context" and args.max_context_cases is not None:
        cases = cases[: args.max_context_cases]
    if args.mode in {"postprocess", "pipeline"} and args.max_postprocess_cases is not None:
        cases = cases[: args.max_postprocess_cases]

    def build_client() -> ChatApiClient:
        return ChatApiClient(
            api_key=args.api_key,
            base_url=args.base_url,
            min_request_interval=args.min_request_interval,
            max_retries=args.max_retries,
            provider_order=args.provider_order,
            provider_sort=args.provider_sort,
            allow_provider_fallbacks=args.allow_provider_fallbacks,
        )

    print_progress(
        "[routing] "
        f"base_url={args.base_url} "
        f"provider_order={args.provider_order or []} "
        f"provider_sort={args.provider_sort or ''} "
        f"allow_provider_fallbacks={args.allow_provider_fallbacks}"
    )

    results: list[dict[str, Any]] = []

    for model in args.models:
        if args.max_concurrency <= 1 or len(cases) <= 1:
            for case in cases:
                results.extend(
                    evaluate_case(
                        client=build_client(),
                        model=model,
                        case=case,
                        args=args,
                        context_variants=context_variants,
                        system_variants=system_variants,
                    )
                )
            continue

        ordered_case_results: list[list[dict[str, Any]] | None] = [None] * len(cases)
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.max_concurrency) as executor:
            future_to_index = {
                executor.submit(
                    evaluate_case,
                    client=build_client(),
                    model=model,
                    case=case,
                    args=args,
                    context_variants=context_variants,
                    system_variants=system_variants,
                ): index
                for index, case in enumerate(cases)
            }
            for future in concurrent.futures.as_completed(future_to_index):
                index = future_to_index[future]
                ordered_case_results[index] = future.result()

        for case_results in ordered_case_results:
            if case_results:
                results.extend(case_results)

    summary = summarize(results)
    payload = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "mode": args.mode,
        "models": args.models,
        "judge_model": args.judge_model,
        "scoring_mode": args.scoring_mode,
        "routing": {
            "base_url": args.base_url,
            "provider_order": args.provider_order or [],
            "provider_sort": args.provider_sort,
            "allow_provider_fallbacks": args.allow_provider_fallbacks,
        },
        "summary": summary,
        "results": results,
    }

    if args.output_json:
        output_path = Path(args.output_json)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print(json.dumps(summary[:10], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
