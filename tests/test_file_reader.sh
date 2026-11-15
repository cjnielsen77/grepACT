#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

printf 'STOP,PLAIN_READER_TEST\n' > "$test_dir/plain.ACT"
printf 'STOP,GZIP_READER_TEST\n' | gzip > "$test_dir/compressed.ACT.gz"

# Extract the function without executing grepACT.sh.
reader_function="$(
    sed -n '/^read_act_files() {/,/^}/p' "$script_dir/grepACT.sh"
)"

# Test both file formats together.
output="$(
    bash -c '
        set -euo pipefail
        eval "$1"
        read_act_files "$2" "$3"
    ' _ "$reader_function" \
      "$test_dir/plain.ACT" \
      "$test_dir/compressed.ACT.gz"
)"

[[ "$output" == *"STOP,PLAIN_READER_TEST"* ]] || {
    echo "FAIL: Plain ACT file was not read"
    exit 1
}

[[ "$output" == *"STOP,GZIP_READER_TEST"* ]] || {
    echo "FAIL: Compressed ACT file was not read"
    exit 1
}

echo "PASS: Direct ACT file reader handles plain and compressed files"
