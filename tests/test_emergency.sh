#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grepact_script="$script_dir/grepACT.sh"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

# Generate synthetic ACT records with emergency numbers
# in the appropriate fields for each record type.
awk 'BEGIN {
    split("START STOP ATTEMPT", types, " ")
    split("16 21 18", fields, " ")

    for (i = 1; i <= 3; i++) {
        for (j = 1; j <= 3; j++) {
            for (k = 1; k <= 21; k++) {
                value[k] = "FIELD" k
            }

            value[1] = types[i]
            value[2] = "CALL_" i "_" j
            value[fields[i]] = (j == 1 ? "911" : j == 2 ? "933" : "4025551234")

            for (k = 1; k <= 21; k++) {
                printf "%s%s", value[k], (k == 21 ? "\n" : ",")
            }
        }
    }
}' > "$test_dir/TEST0001.ACT"

run_test() {
    local type="$1"
    local number="$2"
    local output
    local expected="CALL_${3}"

    output=$(GREPACT_EVLOG_DIR="$test_dir" bash "$grepact_script" \
        -t "$type" -e "$number")

    if [[ $(printf '%s\n' "$output" | grep -Ec '^(START|STOP|ATTEMPT),') -eq 1 ]] &&
       [[ "$output" == *"$expected"* ]]; then
        echo "PASS: $type emergency $number filtering"
    else
        echo "FAIL: $type emergency $number filtering" >&2
        printf '%s\n' "$output" >&2
        return 1
    fi
}

run_test start 911 "1_1"
run_test start 933 "1_2"
run_test stop 911 "2_1"
run_test stop 933 "2_2"
run_test attempt 911 "3_1"
run_test attempt 933 "3_2"

echo "All emergency filtering tests passed."
