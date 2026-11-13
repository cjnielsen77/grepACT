#!/usr/bin/env bash
set -euo pipefail

# Locate grepACT relative to this test script.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grepact_script="$script_dir/grepACT.sh"

# Create an isolated directory for synthetic ACT files.
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

# Create synthetic ACT records.
cat > "$test_dir/BEFORE.ACT" <<'EOF'
STOP,BEFORE_MIDNIGHT,4025551234,4025555678
EOF

cat > "$test_dir/AFTER.ACT" <<'EOF'
STOP,AFTER_MIDNIGHT,4025551234,4025555678
EOF

# Set file modification timestamps in UTC.
TZ=UTC touch -d '2026-10-15 23:30:00' "$test_dir/BEFORE.ACT"
TZ=UTC touch -d '2026-10-16 00:00:00' "$test_dir/AFTER.ACT"

# Execute the actual grepACT script.
output=$(
    TZ=UTC GREPACT_EVLOG_DIR="$test_dir" \
        bash "$grepact_script" \
        -x 10/15/2026 -w 10/15/2026 -t stop
)

# Verify both expected records appear exactly once.
before_count=$(printf '%s\n' "$output" | grep -Fc 'STOP,BEFORE_MIDNIGHT,')
after_count=$(printf '%s\n' "$output" | grep -Fc 'STOP,AFTER_MIDNIGHT,')

if [[ "$before_count" -eq 1 && "$after_count" -eq 1 ]] &&
   [[ "$output" == *"Searching 2 ACT file(s)"* ]]; then
    echo "PASS: Midnight rollover includes both ACT files"
else
    echo "FAIL: Midnight rollover test" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi
