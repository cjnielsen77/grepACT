#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grepact_script="$script_dir/grepACT.sh"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

cat > "$test_dir/TEST0001.ACT" <<'EOF'
ATTEMPT,CALL_001,F3,F4,F5,4025551234,F7,F8,F9,12:30:15,F11,F12,F13,F14,F15,F16,4025551234,7125559999
ATTEMPT,CALL_002,F3,F4,F5,4025551234,F7,F8,F9,12:30:45,F11,F12,F13,F14,F15,F16,4025551234,7125559999
ATTEMPT,CALL_003,F3,F4,F5,4025551234,F7,F8,F9,12:31:15,F11,F12,F13,F14,F15,F16,4025551234,7125559999
ATTEMPT,CALL_004,F3,F4,F5,7125551111,F7,F8,F9,12:30:15,F11,F12,F13,F14,F15,F16,4025551234,7125559999
EOF

output=$(GREPACT_EVLOG_DIR="$test_dir" bash "$grepact_script" \
    -t attempt -u)

if [[ $(printf '%s\n' "$output" | grep -Ec '^ATTEMPT,') -eq 3 ]] &&
   [[ "$output" == *"CALL_001"* ]] &&
   [[ "$output" != *"CALL_002"* ]] &&
   [[ "$output" == *"CALL_003"* ]] &&
   [[ "$output" == *"CALL_004"* ]]; then
    echo "PASS: Duplicate removal preserves unique records"
else
    echo "FAIL: Duplicate removal regression" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

echo "All duplicate removal tests passed."
