#!/usr/bin/env bash
set -euo pipefail

# Locate grepACT relative to this test script.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grepact_script="$script_dir/grepACT.sh"

# Create an isolated directory for synthetic ACT files.
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

# Create synthetic records for a compressed ACT file.
cat > "$test_dir/COMPRESSED.ACT" <<'EOF'
START,GZIP_CALL_001,4025551234,4025555678
STOP,GZIP_CALL_002,4025551234,4025555678
ATTEMPT,GZIP_CALL_003,4025551234,4025555678
EOF

gzip "$test_dir/COMPRESSED.ACT"
gzip -t "$test_dir/COMPRESSED.ACT.gz"

# Scenario 1: Compressed ACT file only.
output=$(
    GREPACT_EVLOG_DIR="$test_dir" \
        bash "$grepact_script" -t stop
)

if [[ "$output" == *"Searching 1 ACT file(s)"* ]] &&
   [[ $(printf '%s\n' "$output" | grep -Fc 'STOP,GZIP_CALL_002,') -eq 1 ]] &&
   [[ "$output" != *"START,GZIP_CALL_"* ]] &&
   [[ "$output" != *"ATTEMPT,GZIP_CALL_"* ]]; then
    echo "PASS: Compressed ACT file filtering"
else
    echo "FAIL: Compressed ACT file filtering" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

# Create an uncompressed ACT file for the mixed-file test.
cat > "$test_dir/UNCOMPRESSED.ACT" <<'EOF'
START,PLAIN_CALL_001,4025551234,4025555678
STOP,PLAIN_CALL_002,4025551234,4025555678
ATTEMPT,PLAIN_CALL_003,4025551234,4025555678
EOF

# Scenario 2: Mixed compressed and uncompressed ACT files.
output=$(
    GREPACT_EVLOG_DIR="$test_dir" \
        bash "$grepact_script" -f 2 -t stop
)

if [[ "$output" == *"Searching 2 ACT file(s)"* ]] &&
   [[ $(printf '%s\n' "$output" | grep -Fc 'STOP,GZIP_CALL_002,') -eq 1 ]] &&
   [[ $(printf '%s\n' "$output" | grep -Fc 'STOP,PLAIN_CALL_002,') -eq 1 ]] &&
   [[ "$output" != *"START,"* ]] &&
   [[ "$output" != *"ATTEMPT,"* ]]; then
    echo "PASS: Mixed compressed/uncompressed ACT filtering"
else
    echo "FAIL: Mixed ACT file filtering" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

echo "All compressed ACT integration tests passed."
