#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

# Create synthetic STOP records with calling and called numbers.
awk 'BEGIN {
    for (i = 1; i <= 3; i++) {
        for (f = 1; f <= 21; f++) {
            value[f] = "FIELD" f
        }

        value[1] = "STOP"
        value[2] = "CALL_00" i
        value[20] = (i == 1 ? "4025551234" : i == 2 ? "402.555.1234" : "402X555X1234")
        value[21] = (i == 1 ? "4025555678" : i == 2 ? "4025558888" : "4025559999")

        for (f = 1; f <= 21; f++) {
            printf "%s%s", value[f], (f == 21 ? "\n" : ",")
        }
    }
}' > "$test_dir/FIELDS.ACT"

run_search() {
    GREPACT_EVLOG_DIR="$test_dir" bash "$script_dir/grepACT.sh" -f 1 -t stop "$@"
}

# Calling number search.
output="$(run_search -n -s 4025551234)"
[[ "$output" == *"STOP,CALL_001,"* ]]
[[ "$output" != *"STOP,CALL_002,"* ]]

# Called number search.
output="$(run_search -o -s 4025558888)"
[[ "$output" == *"STOP,CALL_002,"* ]]
[[ "$output" != *"STOP,CALL_001,"* ]]

# Periods must be treated literally.
output="$(run_search -n -s '402.555.1234')"
[[ "$output" == *"STOP,CALL_002,"* ]]
[[ "$output" != *"STOP,CALL_003,"* ]]

# Calling-number search must not execute shell commands.
marker="$test_dir/injection-marker"
output="$(run_search -n -s "4025551234\$(touch $marker)")"
[[ ! -e "$marker" ]]
[[ "$output" != *"STOP,CALL_001,"* ]]

# Called-number search must not execute shell commands.
output="$(run_search -o -s "4025558888\$(touch $marker)")"
[[ ! -e "$marker" ]]
[[ "$output" != *"STOP,CALL_002,"* ]]

echo "PASS: Field-specific search regression tests"
