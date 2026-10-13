import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def response(message_id, input_tokens=100, output_tokens=10, cached=80, **fields):
    return {
        "type": "function_call",
        "name": "Read",
        "timestamp": 1000,
        "providerData": {
            "messageId": message_id,
            "usage": {
                "inputTokens": input_tokens,
                "outputTokens": output_tokens,
                "inputTokensDetails": [{"cached_tokens": cached}],
            },
        },
        **fields,
    }


class UsageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="statusline test ")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.main = self.write("session.jsonl", [response("main")])

    def write(self, path, records):
        path = self.directory / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(json.dumps(record) + "\n" for record in records))
        return path

    def usage(self):
        result = subprocess.run(
            ["bash", "-c", '''
source "$1/lib/format.sh"
source "$1/lib/parse_input.sh"
tools_mode=simple
source "$1/lib/parse_transcript.sh"
printf '%s %s %s %s %s\n' "$input_tokens" "$output_tokens" "$cache_read_tokens" "$tool_calls" "$runtime"
''', "statusline-test", str(ROOT)],
            input=json.dumps({"transcript_path": str(self.main)}),
            text=True, capture_output=True, check=True,
        )
        return result.stdout.strip()

    def test_main_without_subagents(self):
        self.assertEqual(self.usage(), "100 10 80 1 0s")

    def test_nested_agents_cross_file_dedup_and_session_isolation(self):
        self.write("session/subagents/agent-one.jsonl", [
            response("main"),
            response("child", 200, 20, 150, isSidechain=True, timestamp=9000),
            response("child", 200, 20, 150, type="reasoning"),
        ])
        self.write("session/subagents/agent-one/subagents/agent-two.jsonl", [
            response("child", 200, 20, 150),
            response("nested", 300, 30, 250),
        ])
        self.write("other/subagents/agent-other.jsonl", [response("unrelated")])
        self.assertEqual(self.usage(), "600 60 480 1 0s")

    def test_partial_line_is_counted_when_completed(self):
        child = self.write("session/subagents/agent-one.jsonl", [response("child")])
        partial = json.dumps(response("pending"))
        with child.open("a") as stream:
            stream.write(partial[:25])
        self.assertEqual(self.usage(), "200 20 160 1 0s")
        with child.open("a") as stream:
            stream.write(partial[25:] + "\n")
        self.assertEqual(self.usage(), "300 30 240 1 0s")

    def test_unknown_child_cache_hides_combined_cache(self):
        child = response("child", cached=None)
        self.write("session/subagents/agent-one.jsonl", [child])
        self.assertEqual(self.usage(), "200 20 -1 1 0s")

    def test_record_id_fallback_and_zero_cache(self):
        child = response(None, cached=0, id="record-id")
        self.write("session/subagents/agent-one.jsonl", [child, child])
        self.assertEqual(self.usage(), "200 20 80 1 0s")

    def test_children_count_when_main_has_no_usage(self):
        self.write("session.jsonl", [{"type": "message", "role": "user", "timestamp": 1000}])
        self.write("session/subagents/agent-one.jsonl", [response("child")])
        self.assertEqual(self.usage(), "100 10 80 0 0s")

    def test_claude_latest_main_usage_is_preserved(self):
        def assistant(timestamp, tokens):
            return {"type": "assistant", "timestamp": timestamp,
                    "message": {"usage": {"input_tokens": tokens, "output_tokens": 5}}}

        self.write("session.jsonl", [assistant(1000, 100), assistant(2000, 200)])
        self.write("session/subagents/agent-one.jsonl", [assistant(9000, 900)])
        self.assertEqual(self.usage(), "200 5 0 0 1s")


if __name__ == "__main__":
    unittest.main()
