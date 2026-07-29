#!/usr/bin/env bash
# Run the headless suite and report the two things that matter: the summary line
# and the SCRIPT ERROR count.
#
# docs/ARCHITECTURE.md §20: a GDScript runtime error raised inside a test body
# unwinds only that function and is still reported as a PASS. So "SUITE GREEN" on
# its own is not evidence. Always read the SCRIPT ERROR count next to it.
#
# Usage: tests/run.sh [filter-substring]
set -uo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${LOG:-/tmp/mm-test-run.log}"

if [ $# -gt 0 ]; then
	"$GODOT" --headless --path "$PROJECT" --script tests/run_tests.gd -- "$1" >"$LOG" 2>&1
else
	"$GODOT" --headless --path "$PROJECT" --script tests/run_tests.gd >"$LOG" 2>&1
fi

errors=$(grep -c "SCRIPT ERROR" "$LOG")

echo "--- failures -------------------------------------------------------------"
grep -E "^  FAIL" "$LOG" | head -40
echo "--- summary --------------------------------------------------------------"
grep -E "passed, .* failed|SUITE (GREEN|RED)" "$LOG"
echo "SCRIPT ERROR lines: $errors"
echo "log: $LOG"

# A SCRIPT ERROR is a failure even when the suite claims green.
if [ "$errors" -ne 0 ]; then
	echo "!!! SCRIPT ERROR present — treat as RED"
	grep -n "SCRIPT ERROR" "$LOG" | head -20
	exit 1
fi
grep -q "SUITE GREEN" "$LOG" || exit 1
