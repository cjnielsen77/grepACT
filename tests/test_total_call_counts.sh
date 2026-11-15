#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grepact_script="$script_dir/grepACT.sh"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

# Generate synthetic ACT records with controlled grouping fields.
awk 'BEGIN {
    for (i = 1; i <= 6; i++) {
        for (k = 1; k <= 21; k++)
            value[k] = "FIELD" k

        value[1] = (i <= 3 ? "ATTEMPT" : "STOP")
        value[2] = "CALL_" i
        value[6] = "GROUP_A"
        value[7] = (i == 3 || i == 6 ? "5678XYZ" : "1234XYZ")
        value[12] = (i == 2 ? "31" : "16")
        value[15] = (i == 5 ? "31" : "16")

        for (k = 1; k <= 21; k++)
            printf "%s%s", value[k], (k == 21 ? "\n" : ",")
    }
}' > "$test_dir/TEST0001.ACT"

run_test() {
    GREPACT_EVLOG_DIR="$test_dir" bash "$grepact_script" "$@"
}

# -l without -t includes both record types.
output=$(run_test -l)

if [[ "$output" == *"2 ATTEMPT GROUP_A 1234"* ]] &&
   [[ "$output" == *"1 ATTEMPT GROUP_A 5678"* ]] &&
   [[ "$output" == *"2 STOP GROUP_A 1234"* ]] &&
   [[ "$output" == *"1 STOP GROUP_A 5678"* ]]; then
    echo "PASS: -l counts all record types"
else
    echo "FAIL: -l counts all record types" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# -l with -t limits results to a specific record type.
output=$(run_test -t stop -l)

if [[ "$output" == *"2 STOP GROUP_A 1234"* ]] &&
   [[ "$output" == *"1 STOP GROUP_A 5678"* ]] &&
   [[ "$output" != *"ATTEMPT GROUP_A"* ]]; then
    echo "PASS: -l respects record type"
else
    echo "FAIL: -l respects record type" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# -l with -d filters and groups by disconnect reason.
output=$(run_test -t attempt -l -d 16)

if [[ "$output" == *"1 ATTEMPT GROUP_A 1234 16"* ]] &&
   [[ "$output" == *"1 ATTEMPT GROUP_A 5678 16"* ]] &&
   [[ "$output" != *" 31"* ]]; then
    echo "PASS: -l -d disconnect reason grouping"
else
    echo "FAIL: -l -d disconnect reason grouping" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# -d without -t defaults to ATTEMPT.
output=$(run_test -l -d 16)

if [[ "$output" == *"ATTEMPT GROUP_A"* ]] &&
   [[ "$output" != *"STOP GROUP_A"* ]]; then
    echo "PASS: -l -d defaults to ATTEMPT"
else
    echo "FAIL: -l -d defaults to ATTEMPT" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# -p and -l are mutually exclusive.
if run_test -t stop -l -p 1,6 > "$test_dir/error.log" 2>&1; then
    echo "FAIL: -l accepted incompatible -p" >&2
    exit 1
else
    echo "PASS: -l rejects -p combination"
fi

echo "All total call count tests passed."
