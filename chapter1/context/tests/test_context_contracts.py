#!/usr/bin/env python3
"""Regression: reasoning contracts accept both provider field names.

Ollama's OpenAI-compatible endpoint returns reasoning as `reasoning`;
DeepSeek/Doubao return `reasoning_content`. Before the fix the contract
checks only looked for `reasoning_content`, so a run whose ablation worked
correctly (reasoning genuinely carried in history / genuinely stripped)
was flagged as a violation (observed on real_20261025T064555Z).
"""

import unittest

from run_experiment_1_1 import evaluate_context_contract

TOOLS = [{"type": "function", "function": {"name": "convert_currency"}}]


def _assistant_msg(field, with_tools=True):
    msg = {"role": "assistant", "content": None, field: "step-by-step thoughts"}
    if with_tools:
        msg["tool_calls"] = [{"id": "call-1", "type": "function"}]
    return msg


def _turn_pair(field, strip_from_history=False):
    """Two full-arm turns whose history carries `field`-named reasoning."""
    first_request = {
        "messages": [
            {"role": "system", "content": "system prompt"},
            {"role": "user", "content": "user task"},
        ],
        "tools": TOOLS,
        "tool_choice": "auto",
    }
    history_msgs = [
        {"role": "system", "content": "system prompt"},
        {"role": "user", "content": "user task"},
    ]
    if not strip_from_history:
        history_msgs.append(_assistant_msg(field))
    else:
        # Realistic stripped history: the assistant message is still there
        # (tool_calls retained) but carries no reasoning under any name.
        history_msgs.append(
            {
                "role": "assistant",
                "content": None,
                "tool_calls": [{"id": "call-1", "type": "function"}],
            }
        )
    history_msgs.append(
        {"role": "tool", "tool_call_id": "call-1", "content": "108.7"}
    )
    second_request = {"messages": history_msgs, "tools": TOOLS, "tool_choice": "auto"}
    turn1 = {
        "iteration": 1,
        "request": first_request,
        "response": {"id": "resp-1", "choices": [{"message": _assistant_msg(field)}]},
    }
    turn2 = {
        "iteration": 2,
        "request": second_request,
        "response": {"id": "resp-2", "choices": [{"message": {"role": "assistant", "content": "done"}}]},
    }
    return [turn1, turn2]


class TestFullArmReasoningRetention(unittest.TestCase):
    """reasoning_retained_after_first_turn must accept either field name."""

    def test_deepseek_style_field_retained(self):
        result = evaluate_context_contract("full", _turn_pair("reasoning_content"))
        self.assertTrue(result["reasoning_retained_after_first_turn"])
        self.assertTrue(result["passed"])

    def test_ollama_style_field_retained(self):
        result = evaluate_context_contract("full", _turn_pair("reasoning"))
        self.assertTrue(result["reasoning_retained_after_first_turn"])
        self.assertTrue(result["passed"])

    def test_missing_reasoning_still_fails(self):
        turns = _turn_pair("reasoning")
        for turn in turns:
            for msg in turn["request"]["messages"]:
                msg.pop("reasoning", None)
        result = evaluate_context_contract("full", turns)
        self.assertFalse(result["reasoning_retained_after_first_turn"])
        self.assertFalse(result["passed"])


class TestNoReasoningArmChecks(unittest.TestCase):
    """provider_generated_reasoning / reasoning_removed_from_history."""

    def test_provider_reasoning_detected_in_both_field_names(self):
        for field in ("reasoning_content", "reasoning"):
            result = evaluate_context_contract("no_reasoning", _turn_pair(field))
            self.assertTrue(result["provider_generated_reasoning"], field)

    def test_stripped_history_passes_removal_check(self):
        for field in ("reasoning_content", "reasoning"):
            result = evaluate_context_contract(
                "no_reasoning", _turn_pair(field, strip_from_history=True)
            )
            self.assertTrue(result["reasoning_removed_from_history"], field)

    def test_unstripped_ollama_style_history_fails_removal_check(self):
        # Pre-fix blind spot: history carrying `reasoning` must NOT pass the
        # removal check, or the ablation could silently degenerate.
        result = evaluate_context_contract("no_reasoning", _turn_pair("reasoning"))
        self.assertFalse(result["reasoning_removed_from_history"])


if __name__ == "__main__":
    unittest.main()
