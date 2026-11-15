#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grepact_script="$script_dir/grepACT.sh"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

cat > "$test_dir/TEST0001.ACT" <<'EOF'
STOP,CALL_001,4025551234,4025555678
STOP,CALL_002,4025551234,7125559999
STOP,CALL_003,7125551111,4025555678
EOF

# Verify -v excludes matching records after -s.
output=$(GREPACT_EVLOG_DIR="$test_dir" bash "$grepact_script" \
    -t stop -s "4025551234" -v "7125559999")

expected="STOP,CALL_001,4025551234,4025555678"

if [[ $(printf '%s\n' "$output" | grep -Fxc -- "$expected") -eq 1 ]] &&
   [[ $(printf '%s\n' "$output" | grep -Ec '^STOP,') -eq 1 ]]; then
    echo "PASS: -v excludes matching records"
else
    echo "FAIL: -v excludes matching records" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# Verify periods are interpreted literally.
cat > "$test_dir/TEST0001.ACT" <<'EOF'
STOP,CALL_001,10.20.30.40
STOP,CALL_002,10X20X30X40
EOF

output=$(GREPACT_EVLOG_DIR="$test_dir" bash "$grepact_script" \
    -t stop -v "10.20.30.40")

expected="STOP,CALL_002,10X20X30X40"

if [[ $(printf '%s\n' "$output" | grep -Fxc -- "$expected") -eq 1 ]] &&
   [[ $(printf '%s\n' "$output" | grep -Ec '^STOP,') -eq 1 ]]; then
    echo "PASS: -v literal period handling"
else
    echo "FAIL: -v literal period handling" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

echo "All exclusion search tests passed."
