#!/usr/bin/env bash
set -euo pipefail

# Locate grepACT relative to this test script.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grepact_script="$script_dir/grepACT.sh"

# Create an isolated directory for synthetic ACT files.
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

# Create synthetic records for three different dates.
printf 'STOP,PREVIOUS_DAY,4025551234,4025555678\n' > "$test_dir/PREVIOUS.ACT"
printf 'STOP,TARGET_DAY,4025551234,4025555678\n' > "$test_dir/TARGET.ACT"
printf 'STOP,NEXT_DAY,4025551234,4025555678\n' > "$test_dir/NEXT.ACT"

# Assign predictable modification timestamps.
TZ=UTC touch -d '2026-10-14 15:00:00' "$test_dir/PREVIOUS.ACT"
TZ=UTC touch -d '2026-10-15 14:00:00' "$test_dir/TARGET.ACT"
TZ=UTC touch -d '2026-10-17 10:00:00' "$test_dir/NEXT.ACT"

# Execute grepACT for October 15.
output=$(
    TZ=UTC GREPACT_EVLOG_DIR="$test_dir" \
        bash "$grepact_script" -x 10/15/2026 -t stop
)

# Verify correct inclusion and exclusion.
if [[ "$output" == *"STOP,TARGET_DAY,4025551234,4025555678"* ]] &&
   [[ "$output" != *"STOP,PREVIOUS_DAY,"* ]] &&
   [[ "$output" != *"STOP,NEXT_DAY,"* ]] &&
   [[ "$output" == *"Searching 1 ACT file(s)"* ]]; then
    echo "PASS: Single-date ACT file selection"
else
    echo "FAIL: Single-date ACT file selection" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi
