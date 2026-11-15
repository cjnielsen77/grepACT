#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grepact_script="$script_dir/grepACT.sh"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

# Generate synthetic ACT records with disconnect reasons.
awk 'BEGIN {
    split("STOP ATTEMPT", types, " ")
    split("15 12", fields, " ")

    for (i = 1; i <= 2; i++) {
        for (j = 1; j <= 2; j++) {
            for (k = 1; k <= 21; k++)
                value[k] = "FIELD" k

            value[1] = types[i]
            value[2] = "CALL_" i "_" j
            value[fields[i]] = (j == 1 ? "16" : "31")

            for (k = 1; k <= 21; k++)
                printf "%s%s", value[k], (k == 21 ? "\n" : ",")
        }
    }
}' > "$test_dir/TEST0001.ACT"

run_test() {
    local type="$1"
    local reason="$2"
    local expected="$3"
    local output

    output=$(GREPACT_EVLOG_DIR="$test_dir" bash "$grepact_script" \
        -t "$type" -d "$reason")

    if [[ $(printf '%s\n' "$output" | grep -Ec '^(START|STOP|ATTEMPT),') -eq 1 ]] &&
       [[ "$output" == *"$expected"* ]]; then
        echo "PASS: $type disconnect reason $reason"
    else
        echo "FAIL: $type disconnect reason $reason" >&2
        printf '%s\n' "$output" >&2
        return 1
    fi
}

run_test stop 16 "CALL_1_1"
run_test stop 31 "CALL_1_2"
run_test attempt 16 "CALL_2_1"
run_test attempt 31 "CALL_2_2"

# START records do not contain a disconnect reason.
if GREPACT_EVLOG_DIR="$test_dir" bash "$grepact_script" \
    -t start -d 16 > "$test_dir/error.log" 2>&1; then
    echo "FAIL: START accepted a disconnect reason" >&2
    exit 1
else
    echo "PASS: START rejects disconnect reason"
fi

echo "All disconnect reason tests passed."
