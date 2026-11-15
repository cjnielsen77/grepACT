#!/usr/bin/env bash
set -euo pipefail

# Locate the grepACT script relative to this test file.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grepact_script="$script_dir/grepACT.sh"

# Create an isolated directory for synthetic ACT files.
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

# Create synthetic test records.
cat > "$test_dir/TEST0001.ACT" <<'EOF'
START,TEST_CALL_001,4025551234,4025555678
STOP,TEST_CALL_002,4025551234,4025555678
ATTEMPT,TEST_CALL_003,4025551234,4025555678
EOF

# Run grepACT and verify the expected record is present.
run_test() {
    local record_type="$1"
    local expected_record="$2"
    local output

    output=$(GREPACT_EVLOG_DIR="$test_dir" bash "$grepact_script" -t "$record_type")

    if [[ $(printf '%s\n' "$output" | grep -Fxc -- "$expected_record") -eq 1 ]] &&
       [[ $(printf '%s\n' "$output" | grep -Ec '^(START|STOP|ATTEMPT),') -eq 1 ]]; then
        echo "PASS: $record_type filtering"
    else
        echo "FAIL: $record_type filtering" >&2
        printf '%s\n' "$output" >&2
        return 1
    fi
}

run_test start "START,TEST_CALL_001,4025551234,4025555678"
run_test stop "STOP,TEST_CALL_002,4025551234,4025555678"
run_test attempt "ATTEMPT,TEST_CALL_003,4025551234,4025555678"

echo "All basic integration tests passed."
