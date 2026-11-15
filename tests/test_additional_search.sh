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

# -z must narrow the results already matched by -s.
output=$(GREPACT_EVLOG_DIR="$test_dir" bash "$grepact_script" \
    -t stop -s "4025551234" -z "4025555678")

expected="STOP,CALL_001,4025551234,4025555678"

if [[ $(printf '%s\n' "$output" | grep -Fxc -- "$expected") -eq 1 ]] &&
   [[ $(printf '%s\n' "$output" | grep -Ec '^(START|STOP|ATTEMPT),') -eq 1 ]]; then
    echo "PASS: -z additional search filtering"
else
    echo "FAIL: -z additional search filtering" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# Verify that periods are treated literally.
cat > "$test_dir/TEST0001.ACT" <<'EOF'
STOP,CALL_001,10.20.30.40
STOP,CALL_002,10X20X30X40
EOF

output=$(GREPACT_EVLOG_DIR="$test_dir" bash "$grepact_script" \
    -t stop -z "10.20.30.40")

if [[ $(printf '%s\n' "$output" | grep -Ec '^STOP,') -eq 1 ]] &&
   [[ "$output" == *"STOP,CALL_001,10.20.30.40"* ]]; then
    echo "PASS: -z literal period handling"
else
    echo "FAIL: -z literal period handling" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

echo "All additional search tests passed."
