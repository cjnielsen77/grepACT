#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grepact_script="$script_dir/grepACT.sh"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

cat > "$test_dir/TEST0001.ACT" <<'EOF'
STOP,CALL_001,4025551234,7125559999
STOP,CALL_002,4025551234,7125559999
STOP,CALL_003,7125551111,4025555678
EOF

run_test() {
    local output
    output=$(GREPACT_EVLOG_DIR="$test_dir" bash "$grepact_script" \
        -t stop "$@")

    printf '%s\n' "$output"
}

# Basic field selection.
output=$(run_test -p 3,4)

if [[ $(printf '%s\n' "$output" |
    grep -Fxc '4025551234 7125559999') -eq 2 ]] &&
   [[ $(printf '%s\n' "$output" |
    grep -Fxc '7125551111 4025555678') -eq 1 ]]; then
    echo "PASS: -p basic field selection"
else
    echo "FAIL: -p basic field selection" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# Field selection with counts.
output=$(run_test -p 3,4 -c)

if [[ "$output" == *"2 4025551234 7125559999"* ]] &&
   [[ "$output" == *"1 7125551111 4025555678"* ]]; then
    echo "PASS: -p -c field counting"
else
    echo "FAIL: -p -c field counting" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# Field selection with -i.
output=$(run_test -p 3,4 -i)

if [[ $(printf '%s\n' "$output" |
    grep -Fxc '4025551234 7125559999') -eq 2 ]]; then
    echo "PASS: -p -i field selection"
else
    echo "FAIL: -p -i field selection" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# Field selection with counting and -i.
output=$(run_test -p 3,4 -c -i)

if [[ "$output" == *"2 4025551234 7125559999"* ]]; then
    echo "PASS: -p -c -i field counting"
else
    echo "FAIL: -p -c -i field counting" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# Verify existing quoted-field behavior without -i.
cat > "$test_dir/TEST0001.ACT" <<'EOF'
STOP,CALL_001,"VARIANT",4025551234,7125559999
EOF

output=$(run_test -p 2,3)

if [[ $(printf '%s\n' "$output" |
    grep -Fxc 'CALL_001 "') -eq 1 ]]; then
    echo "PASS: -p quoted-field handling"
else
    echo "FAIL: -p quoted-field handling" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# Verify -i preserves the quoted content.
output=$(run_test -p 2,3 -i)

if [[ $(printf '%s\n' "$output" |
    grep -Fxc 'CALL_001 "VARIANT"') -eq 1 ]]; then
    echo "PASS: -p -i preserves quoted content"
else
    echo "FAIL: -p -i quoted-field handling" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# Reject invalid field selections.
if GREPACT_EVLOG_DIR="$test_dir" bash "$grepact_script" \
    -t stop -p "3;whoami" > "$test_dir/error.log" 2>&1; then
    echo "FAIL: Invalid -p field selection accepted" >&2
    exit 1
else
    echo "PASS: Invalid -p field selection rejected"
fi

echo "All print field tests passed."
