#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grepact_script="$script_dir/grepACT.sh"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

# Generate synthetic ATTEMPT and STOP records.
awk 'BEGIN {
    for (i = 1; i <= 6; i++) {
        for (k = 1; k <= 21; k++)
            value[k] = "FIELD" k

        value[1] = (i <= 3 ? "ATTEMPT" : "STOP")
        value[2] = "CALL_" i
        value[6] = "GROUP_A"

        if (i <= 3) {
            value[10] = (i == 3 ? "1231XYZ" : "1230XYZ")
            value[12] = (i == 2 ? "31" : "16")
        } else {
            value[12] = (i == 6 ? "1231XYZ" : "1230XYZ")
            value[15] = (i == 5 ? "31" : "16")
        }

        for (k = 1; k <= 21; k++)
            printf "%s%s", value[k], (k == 21 ? "\n" : ",")
    }
}' > "$test_dir/TEST0001.ACT"

run_test() {
    GREPACT_EVLOG_DIR="$test_dir" bash "$grepact_script" "$@"
}

# ATTEMPT grouping.
output=$(run_test -t attempt -j)

if [[ "$output" == *"GROUP_A 1230 16"* ]] &&
   [[ "$output" == *"GROUP_A 1230 31"* ]] &&
   [[ "$output" == *"GROUP_A 1231 16"* ]]; then
    echo "PASS: -j ATTEMPT grouping"
else
    echo "FAIL: -j ATTEMPT grouping" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# STOP grouping.
output=$(run_test -t stop -j)

if [[ "$output" == *"GROUP_A 1230 16"* ]] &&
   [[ "$output" == *"GROUP_A 1230 31"* ]] &&
   [[ "$output" == *"GROUP_A 1231 16"* ]]; then
    echo "PASS: -j STOP grouping"
else
    echo "FAIL: -j STOP grouping" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# -j without -t defaults to ATTEMPT.
output=$(run_test -j)

if [[ "$output" == *"GROUP_A 1230 16"* ]] &&
   [[ "$output" == *"GROUP_A 1230 31"* ]] &&
   [[ "$output" == *"GROUP_A 1231 16"* ]]; then
    echo "PASS: -j defaults to ATTEMPT"
else
    echo "FAIL: -j defaults to ATTEMPT" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# START is unsupported.
if run_test -t start -j > "$test_dir/error.log" 2>&1; then
    echo "FAIL: -j accepted START records" >&2
    exit 1
else
    echo "PASS: -j rejects START"
fi

# -j and -l cannot be combined.
if run_test -j -l > "$test_dir/error.log" 2>&1; then
    echo "FAIL: -j accepted incompatible -l" >&2
    exit 1
else
    echo "PASS: -j rejects -l combination"
fi

# -j and -p cannot be combined.
if run_test -j -p 1,6 > "$test_dir/error.log" 2>&1; then
    echo "FAIL: -j accepted incompatible -p" >&2
    exit 1
else
    echo "PASS: -j rejects -p combination"
fi

echo "All time disposition tests passed."
