#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

marker="$test_dir/injection-marker"

# Use a relative marker name so the ACT filenames contain no slashes.
plain_file='PLAIN$(touch injection-marker).ACT'
gzip_file='COMPRESSED$(touch injection-marker).ACT.gz'

# Create synthetic ACT records.
printf 'STOP,PLAIN_TEST,4025551234,4025555678\n' > "$test_dir/$plain_file"
printf 'STOP,GZIP_TEST,4025551234,4025555678\n' | gzip > "$test_dir/$gzip_file"

# Run the script against both files.
output="$(GREPACT_EVLOG_DIR="$test_dir" bash "$script_dir/grepACT.sh" -f 2 -t stop)"

# Neither filename should execute shell commands.
if [[ -e "$marker" ]]; then
    echo "FAIL: Filename executed shell code"
    exit 1
fi

# Both files should be processed successfully.
if [[ "$output" != *"STOP,PLAIN_TEST,"* ]]; then
    echo "FAIL: Uncompressed ACT file was not processed"
    exit 1
fi

if [[ "$output" != *"STOP,GZIP_TEST,"* ]]; then
    echo "FAIL: Compressed ACT file was not processed"
    exit 1
fi

echo "PASS: ACT filenames were handled safely"
