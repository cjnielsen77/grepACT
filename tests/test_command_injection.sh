#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grepact_script="$script_dir/grepACT.sh"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

cat > "$test_dir/TEST.ACT" <<'EOF'
STOP,SAFE_CALL_001,4025551234,4025555678
EOF

marker="$test_dir/injection-marker"

# Test whether a search string can execute a shell command.
output=$(
    GREPACT_EVLOG_DIR="$test_dir" \
        bash "$grepact_script" -t stop \
        -s "SAFE_CALL_001\$(touch $marker)"
)

if [[ -e "$marker" ]]; then
    echo "FAIL: User-supplied search executed a shell command" >&2
    exit 1
fi

if [[ "$output" == *"STOP,SAFE_CALL_001,"* ]]; then
    echo "FAIL: Search unexpectedly matched after command substitution" >&2
    exit 1
fi

echo "PASS: Search input was not executed as shell code"
