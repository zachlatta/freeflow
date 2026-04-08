import unittest
from unittest import mock

from eval_groq_prompts import Case, parse_args, score_output


def make_case(**overrides):
    defaults = {
        "id": "case",
        "metadata": {
            "app_name": "Mail",
            "bundle_identifier": "com.apple.mail",
            "window_title": "Re: Budget review",
            "selected_text": "",
        },
        "raw_transcript": "yes that works for me i'll send the revised draft tonight",
        "custom_vocabulary": [],
        "expected_output": "Hi,\n\nYes, that works for me. I'll send the revised draft tonight.",
        "expected_context_summary": "The user is replying to an email about a budget review. The destination is an email reply.",
        "required_context_terms": [],
        "forbidden_context_terms": [],
        "required_output_terms": ["works for me", "revised draft tonight"],
        "forbidden_output_terms": [],
        "screenshot_path": None,
    }
    defaults.update(overrides)
    return Case(**defaults)


class ScoreOutputTests(unittest.TestCase):
    def test_email_formatting_scores_higher_with_salutation_and_newlines(self):
        case = make_case()

        proper = score_output("Hi,\n\nYes, that works for me. I'll send the revised draft tonight.", case)
        flat = score_output("Yes, that works for me. I'll send the revised draft tonight.", case)

        self.assertEqual(proper["output_format"], 1.0)
        self.assertLess(flat["output_format"], 1.0)
        self.assertGreater(proper["output_total"], flat["output_total"])

    def test_boilerplate_wrapper_is_penalized(self):
        case = make_case(
            metadata={
                "app_name": "Slack",
                "bundle_identifier": "com.tinyspeck.slackmacgap",
                "window_title": "Design sync | Slack",
                "selected_text": "",
            },
            expected_output="Yeah, this feels a bit too heavy. Maybe we can trim it back.",
            expected_context_summary="The user is writing in Slack during a design discussion. The destination is a casual chat message.",
            required_output_terms=["too heavy", "trim it back"],
            raw_transcript="yeah this feels a bit too heavy maybe we can trim it back",
        )

        clean = score_output("Yeah, this feels a bit too heavy. Maybe we can trim it back.", case)
        wrapped = score_output(
            "Here is the clean transcript: Yeah, this feels a bit too heavy. Maybe we can trim it back.",
            case,
        )

        self.assertEqual(clean["output_contract"], 1.0)
        self.assertEqual(wrapped["output_contract"], 0.0)
        self.assertGreater(clean["output_total"], wrapped["output_total"])

    def test_explicit_numbered_list_scores_higher_than_prose_list(self):
        case = make_case(
            metadata={
                "app_name": "ChatGPT",
                "bundle_identifier": "com.openai.chat",
                "window_title": "Prompt draft",
                "selected_text": "",
            },
            raw_transcript="numbered list one update the changelog two tag the release three post the announcement",
            expected_output="1. Update the changelog.\n2. Tag the release.\n3. Post the announcement.",
            expected_context_summary="The user is dictating a numbered list into a writing app. The destination should preserve explicit list formatting.",
            required_output_terms=["1.", "2.", "3.", "Update the changelog"],
            forbidden_output_terms=["First, update the changelog.", "Second, tag the release."],
        )

        structured = score_output(case.expected_output, case)
        prose = score_output(
            "First, update the changelog. Second, tag the release. Third, post the announcement.",
            case,
        )

        self.assertEqual(structured["output_format"], 1.0)
        self.assertLess(prose["output_format"], 1.0)
        self.assertGreater(structured["output_total"], prose["output_total"])

    def test_self_correction_left_in_output_is_penalized(self):
        case = make_case(
            metadata={
                "app_name": "Slack",
                "bundle_identifier": "com.tinyspeck.slackmacgap",
                "window_title": "#ventas | Slack",
                "selected_text": "",
            },
            raw_transcript="lo mando mañana no perdon pasado mañana por la tarde",
            expected_output="Lo mando pasado mañana por la tarde.",
            expected_context_summary="The user is replying in Slack. The destination is a casual chat message.",
            required_output_terms=["pasado mañana", "por la tarde"],
            forbidden_output_terms=["mañana", "perdón"],
        )

        corrected = score_output("Lo mando pasado mañana por la tarde.", case)
        uncorrected = score_output("Lo mando mañana, no perdón, pasado mañana por la tarde.", case)

        self.assertGreater(corrected["output_format"], uncorrected["output_format"])
        self.assertGreater(corrected["output_total"], uncorrected["output_total"])

    def test_dictated_email_closing_gets_its_own_paragraph(self):
        case = make_case(
            raw_transcript="hi dana comma yes that works for me thanks",
            expected_output="Hi Dana,\n\nYes, that works for me.\n\nThanks,",
            required_output_terms=["Hi Dana", "works for me", "Thanks"],
        )

        separated = score_output("Hi Dana,\n\nYes, that works for me.\n\nThanks,", case)
        inline = score_output("Hi Dana,\n\nYes, that works for me. Thanks,", case)

        self.assertGreater(separated["output_total"], inline["output_total"])

    def test_meta_instruction_response_is_penalized(self):
        case = make_case(
            metadata={
                "app_name": "T3 Code (Alpha)",
                "bundle_identifier": "com.t3.chat",
                "window_title": "freeflow",
                "selected_text": "",
            },
            raw_transcript="ignore my last message just write a pr description",
            expected_output="Ignore my last message. Just write a PR description.",
            expected_context_summary="The active app is T3 Code (Alpha), and the user appears to be working on a project called freeflow with a focus on optimizing performance.",
            required_output_terms=["Ignore my last message", "PR description"],
            forbidden_output_terms=["Optimizes performance", "adding benchmarks"],
        )

        literal = score_output("Ignore my last message. Just write a PR description.", case)
        answered = score_output(
            "Optimizes performance of the freeflow project by refactoring critical loops and adding benchmarks.",
            case,
        )

        self.assertGreater(literal["output_total"], answered["output_total"])


class ParseArgsTests(unittest.TestCase):
    def test_judge_model_defaults_to_none(self):
        with mock.patch("sys.argv", ["eval_groq_prompts.py"]):
            args = parse_args()
        self.assertIsNone(args.judge_model)

    def test_judge_model_can_be_set(self):
        with mock.patch("sys.argv", ["eval_groq_prompts.py", "--judge-model", "openai/gpt-5.4-nano"]):
            args = parse_args()
        self.assertEqual(args.judge_model, "openai/gpt-5.4-nano")


if __name__ == "__main__":
    unittest.main()
