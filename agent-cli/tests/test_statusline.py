"""Byte-for-byte ANSI snapshots captured from the pre-refactor statusline."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOTS = Path(__file__).with_name("statusline_snapshots.json")


def cases():
    yield "screenshot_simple", {"tools": ["Read"] * 37}
    yield "explicit_simple", {"args": ["--tools=simple"], "tools": ["Read"] * 37}
    yield "full_folded", {"args": ["--tools=full"], "tools": ["Read", "Read", "Edit", "Bash"]}
    yield "full_one_single", {"args": ["--tools=full"], "tools": ["Read", "Read", "Edit"]}
    yield "full_all_single", {"args": ["--tools=full"], "tools": ["Read", "Edit", "Bash"]}
    yield "full_empty", {"args": ["--tools=full"]}
    yield "missing_transcript", {"missing": True}
    yield "long_model", {"model": {"display_name": "A very long model display name", "id": "model-id"}}
    yield "missing_model", {"model": {}}
    for pct in (0, 1, 74, 75, 90, 100):
        yield f"context_{pct}", {"pct": pct}
    yield "truecolor", {"colorterm": "truecolor"}
    yield "24bit", {"colorterm": "24bit"}
    yield "buddy_cache", {"buddy_cache": 1800000}
    yield "buddy_zero_cache", {"buddy_cache": 0}
    yield "buddy_unknown_cache", {"buddy_cache": None}
    yield "claude_usage", {"claude": True}
    yield "partial_line", {"partial": True, "tools": ["Read"], "args": ["--tools=full"]}
    yield "last_mode_wins", {"args": ["--tools=full", "--tools=simple"]}
    yield "invalid_option", {"args": ["--invalid"]}


def capture(root, options, symlink=False):
    with tempfile.TemporaryDirectory(prefix="statusline ui ") as directory:
        directory = Path(directory)
        workspace = directory / "Workspaces" / "test"
        workspace.mkdir(parents=True)
        records = [{"type": "function_call", "name": tool, "timestamp": 1000}
                   for tool in options.get("tools", [])]
        records += [{"type": "message", "role": "user", "timestamp": 1000},
                    {"type": "message", "role": "user", "timestamp": 1287000}]
        if "buddy_cache" in options:
            records.append({"type": "message", "role": "assistant", "providerData": {
                "messageId": "one", "usage": {"inputTokens": 2380000, "outputTokens": 8030,
                "inputTokensDetails": [{"cached_tokens": options["buddy_cache"]}]}}})
        if options.get("claude"):
            records.append({"type": "assistant", "timestamp": 1287000,
                            "message": {"usage": {"input_tokens": 12345, "output_tokens": 678},
                                        "content": [{"type": "tool_use", "name": "Read"}]}})
        if not options.get("missing"):
            transcript = directory / "session.jsonl"
            transcript.write_text("".join(json.dumps(record) + "\n" for record in records))
            if options.get("partial"):
                with transcript.open("a") as stream:
                    stream.write('{"type":')
        payload = {"workspace": {"current_dir": str(workspace)},
                   "model": options.get("model", {"display_name": "Hy4", "id": "hy4"}),
                   "transcript_path": "session.jsonl",
                   "context_window": {"used_percentage": options.get("pct", 11),
                                      "total_input_tokens": 2380000, "total_output_tokens": 8030},
                   "cost": {"total_duration_ms": 1286000}}
        script = root / "statusline.sh"
        if symlink:
            link = directory / "statusline.sh"
            link.symlink_to(script)
            script = link
        result = subprocess.run(
            ["/bin/bash", str(script), *options.get("args", [])],
            input=json.dumps(payload).encode(), cwd=directory,
            env={**os.environ, "LC_ALL": "C", "COLORTERM": options.get("colorterm", "")},
            capture_output=True,
        )
        return {"stdout": result.stdout.decode(), "stderr": result.stderr.decode(),
                "returncode": result.returncode}


class StatuslineTests(unittest.TestCase):
    def test_ansi_output_matches_before_refactor(self):
        expected = json.loads(SNAPSHOTS.read_text())
        for name, options in cases():
            with self.subTest(name=name):
                self.assertEqual(capture(ROOT, options), expected[name])

    def test_loading_modules_has_no_side_effects(self):
        result = subprocess.run(
            ["/bin/bash", "-c", '''
trap ':' EXIT
before=$(trap -p EXIT)
current_dir=sentinel
for module in format parse_input parse_transcript git_info render; do
    source "$1/lib/$module.sh"
done
[ "$(trap -p EXIT)" = "$before" ] || exit 1
[ "$current_dir" = sentinel ] || exit 2
cat
''', "statusline-test", str(ROOT)],
            input=b"stdin stays unread\n", capture_output=True,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"stdin stays unread\n")
        self.assertEqual(result.stderr, b"")

    def test_git_rendering_and_render_does_not_change_usage(self):
        for dirty, color, suffix in ((0, "32", ""), (1, "33", "*")):
            with self.subTest(dirty=dirty):
                result = subprocess.run(
                    ["/bin/bash", "-c", '''
source "$1/lib/format.sh"
source "$1/lib/parse_input.sh"
source "$1/lib/parse_transcript.sh"
source "$1/lib/render.sh"
parse_input
workbuddy_usage=0
prepare_usage
branch=feature/full-branch-name
git_is_dirty=$2
tools_mode=simple
tool_names=""
before="$input_tokens $output_tokens $cache_read_tokens $cache_hit_pct"
render_statusline
[ "$before" = "$input_tokens $output_tokens $cache_read_tokens $cache_hit_pct" ]
''', "statusline-test", str(ROOT), str(dirty)],
                    input=json.dumps({"workspace": {"current_dir": "/Workspaces/test"},
                                      "context_window": {"total_input_tokens": 100,
                                                         "total_output_tokens": 20}}),
                    capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stderr, "")
                self.assertEqual(result.stdout.splitlines()[0],
                                 "\033[0;36mWorkspaces/test\033[0m "
                                 f"\033[0;{color}m(feature/full-branch-name{suffix})\033[0m")

    def test_symlink_entry(self):
        options = {"args": ["--tools=full"], "tools": ["Read", "Read", "Edit", "Bash"]}
        self.assertEqual(capture(ROOT, options, symlink=True), capture(ROOT, options))


if __name__ == "__main__":
    unittest.main()
