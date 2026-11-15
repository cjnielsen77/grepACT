#!/usr/bin/env bash
set -euo pipefail

# Locate grepACT relative to this test script.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grepact_script="$script_dir/grepACT.sh"

# Create an isolated test directory.
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

# Verify an invalid command fails with the expected
# exit code and error message.
run_error_test() {
    local test_name="$1"
    local expected_code="$2"
    local expected_message="$3"
    local log_dir="$4"
    shift 4

    local output
    local actual_code=0

    output=$(
        GREPACT_EVLOG_DIR="$log_dir" \
            bash "$grepact_script" "$@" 2>&1
    ) || actual_code=$?

    if [[ "$actual_code" -eq "$expected_code" ]] &&
       [[ "$output" == *"$expected_message"* ]]; then
        echo "PASS: $test_name"
    else
        echo "FAIL: $test_name" >&2
        echo "Expected exit code: $expected_code" >&2
        echo "Actual exit code: $actual_code" >&2
        echo "Expected message: $expected_message" >&2
        printf 'Actual output:\n%s\n' "$output" >&2
        return 1
    fi
}

# Test 1: Invalid record type.
run_error_test \
    "Invalid record type" \
    64 \
    "Invalid -t value. Use start, stop, or attempt." \
    "$test_dir" \
    -t invalid

# Test 2: Invalid file count.
run_error_test \
    "Invalid file count" \
    64 \
    "-f requires a numeric value: abc" \
    "$test_dir" \
    -f abc

# Test 3: Missing ACT directory.
run_error_test \
    "Missing ACT directory" \
    66 \
    "directory not found:" \
    "$test_dir/nonexistent" \
    -t stop

echo "All error-handling tests passed."
