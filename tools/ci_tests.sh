#!/usr/bin/env bash
# The tests GitHub runs on every pull request (.github/workflows/tests.yml).
# GitHub's machines have no graphics card, so this runs a short set of tests that work with
# software drawing (OpenGL under a fake screen). The full Forward+ set still runs on the PC
# with tools/run_tests.ps1.
#
#   tools/ci_tests.sh <engine executable> [test names...]
#
# A test counts as passed when it printed its "DONE fails=0" line and no FAIL or script error.
# The exit code is not used: the NDI add-on can crash the engine while it quits (exit 134),
# after every result was already printed.
set -u

ENGINE="${1:?usage: tools/ci_tests.sh <engine executable> [test names...]}"
ENGINE="$(realpath "$ENGINE")"
shift
# Fast tests that are reliable without a GPU (about 3 minutes together on a GitHub machine).
TESTS=("$@")
if [ ${#TESTS[@]} -eq 0 ]; then
	TESTS=(test_odd_text test_emote_urls test_together_limits test_capture_key test_status_line test_panel_tidy)
fi
TIME_LIMIT="${TIME_LIMIT:-240}"   # seconds per test before it is stopped
OUT="${OUT:-/tmp/sr_tests}"       # logs and screenshots, outside the project folder
mkdir -p "$OUT"
cd "$(dirname "$0")/.."

failed=()
for t in "${TESTS[@]}"; do
	log="$OUT/$t.log"
	start=$(date +%s)
	timeout -k 10 "$TIME_LIMIT" xvfb-run -a "$ENGINE" --rendering-driver opengl3 --path . \
		"res://_tests/$t.tscn" -- "$OUT/$t" --mp-profile=test > "$log" 2>&1
	code=$?
	secs=$(( $(date +%s) - start ))
	done_line=$(grep -o 'DONE fails=[0-9]*' "$log" | tail -n 1)
	problems=$(grep -E '^FAIL|SCRIPT ERROR|Parse Error|Failed to load script' "$log")
	if [ "$done_line" = "DONE fails=0" ] && [ -z "$problems" ]; then
		echo "PASS  $t  (${secs}s, exit $code)"
	else
		echo "FAIL  $t  (${secs}s, exit $code, ${done_line:-no DONE line})"
		[ -n "$problems" ] && echo "$problems" | head -n 40 | sed 's/^/      /'
		echo "      --- last lines of $log ---"
		tail -n 30 "$log" | sed 's/^/      /'
		failed+=("$t")
	fi
done

if [ ${#failed[@]} -gt 0 ]; then
	echo "Failed: ${failed[*]}"
	exit 1
fi
echo "All ${#TESTS[@]} tests passed."
