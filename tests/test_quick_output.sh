#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

printf 'STOP,PLAIN_QUICK_TEST\n' > "$test_dir/plain.ACT"
printf 'STOP,GZIP_QUICK_TEST\n' | gzip > "$test_dir/compressed.ACT.gz"


# Verify -q includes both compressed and uncompressed ACT files.
output="$(
    GREPACT_EVLOG_DIR="$test_dir" \
        bash "$script_dir/grepACT.sh" -f 2 -t stop -q 10
)"

if [[ "$output" != *"STOP,PLAIN_QUICK_TEST"* ]]; then
    echo "FAIL: -q skipped the uncompressed ACT file"
    exit 1
fi

if [[ "$output" != *"STOP,GZIP_QUICK_TEST"* ]]; then
    echo "FAIL: -q skipped the compressed ACT file"
    exit 1
fi

echo "PASS: -q includes both ACT file formats"

# Verify -Q includes both compressed and uncompressed ACT files.
output="$(
    GREPACT_EVLOG_DIR="$test_dir" \
        bash "$script_dir/grepACT.sh" -f 2 -t stop -Q 10
)"

if [[ "$output" != *"STOP,PLAIN_QUICK_TEST"* ]]; then
    echo "FAIL: -Q skipped the uncompressed ACT file"
    exit 1
fi

if [[ "$output" != *"STOP,GZIP_QUICK_TEST"* ]]; then
    echo "FAIL: -Q skipped the compressed ACT file"
    exit 1
fi

echo "PASS: -Q includes both ACT file formats"
