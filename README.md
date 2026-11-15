# grepACT

[![grepACT CI](https://github.com/cjnielsen77/grepACT/actions/workflows/ci.yml/badge.svg)](https://github.com/cjnielsen77/grepACT/actions/workflows/ci.yml)

**grepACT** is a Bash command-line utility for searching and analyzing Ribbon / Sonus Session Border Controller (SBC) ACT call detail records (CDRs). It helps voice engineers investigate SIP call attempts, disconnect reasons, routing behavior, emergency calls, and patterns across high-volume call records without manually opening individual log files.

Developed for operational troubleshooting in a large enterprise voice environment, grepACT handles both uncompressed `.ACT` and gzip-compressed `.ACT.gz` files, supports targeted searches and date-based selection, and produces field-level summaries useful for incident investigation and monitoring.

## Features

- **Record filtering:** Search `START`, `STOP`, or `ATTEMPT` records, or all three together.
- **Flexible searches:** Match case-insensitive patterns, add inclusion or exclusion filters, or search calling/called-number fields specifically.
- **File selection:** Search the latest file, a specified number of files, today, yesterday, the past week, a particular date, or a date range.
- **Compressed logs:** Read `.ACT` and `.ACT.gz` files in a single search.
- **Call investigation:** Filter emergency numbers (`911` / `933`) and disconnect reasons; remove duplicate ATTEMPT records using ACT fields.
- **Reporting:** Extract selected fields, count repeated field combinations, summarize call counts, and group time-disposition results.
- **Quick inspection:** Limit output to the first or last *n* matching lines.
- **SALT extraction:** Retrieve recent STOP and ATTEMPT records for a specialized monitoring workflow.

The utility is intended for environments producing large volumes of CDRs. Actual performance depends on file sizes, storage, compression, and the filters used.

## Requirements

- Linux with **Bash 4+** and GNU utilities
- `awk`, `grep`, `sed`, `cut`, `sort`, `uniq`, `find`, `date`, `cat`, and `gzip` (for compressed files)
- Read access to the directory containing Ribbon / Sonus ACT logs

The default log directory is `/var/log/sonus/sbx/evlog/`. Override it with `GREPACT_EVLOG_DIR` when testing or using a different installation layout. The original operational environment used the `linuxadmin` account; the script itself needs appropriate file permissions, not a particular username.

**Date-selection assumption:** The script's date-based file selection uses filesystem modification times and logic built around ACT rollover at **00:00:00 UTC/GMT**. Verify rollover behavior and timestamp handling in your environment before relying on date-boundary searches.

## Installation

```bash
git clone https://github.com/cjnielsen77/grepACT.git
cd grepACT
chmod +x grepACT.sh
```

On an SBC or another host with access to ACT files:

```bash
./grepACT.sh -h
./grepACT.sh -t stop -s 4025551234
```

To point the script at a separate directory of ACT files:

```bash
GREPACT_EVLOG_DIR=/path/to/act/files ./grepACT.sh -t attempt -s 4025551234
```

The script reads ACT records and writes results to standard output; it does not edit the source ACT files. Temporary files are used by the SALT processing path and removed on exit.

## Command-line options

### File selection

| Option | Description |
| --- | --- |
| `-f <n>` | Search the most recent *n* ACT files (default: 1). |
| `-y today\|yest\|week` | Search files selected for today, yesterday, or the last seven days. |
| `-x MM/DD/YYYY` | Search files for a specific date. |
| `-w MM/DD/YYYY` | End date for a range; requires `-x`. |
| `-m` | SALT recent-traffic extraction mode; cannot be combined with other options. |

### Record filters

| Option | Description |
| --- | --- |
| `-t start\|stop\|attempt` | Select a CDR record type; defaults to all three. |
| `-s <pattern>` | Case-insensitive search; comma-separated terms act as OR alternatives. |
| `-z <pattern>` | Additional case-insensitive include filter. |
| `-v <pattern>` | Exclude matching records. |
| `-n` | With `-s`, search the calling-number field; requires STOP or ATTEMPT. |
| `-o` | With `-s`, search the called-number field; requires STOP or ATTEMPT. |
| `-e 911\|933` | Filter emergency called numbers; requires an explicit record type. |
| `-d <reason>` | Filter by disconnect reason (ATTEMPT field 12; STOP field 15). |
| `-u` | Remove duplicate ATTEMPT records based on selected call fields. |

### Output and diagnostics

| Option | Description |
| --- | --- |
| `-p <fields>` | Print selected 1-based comma-separated CSV field numbers or ranges, such as `1,6,10-12`. |
| `-c` | With `-p`, count identical selected-field combinations. Also accepted with `-j`. |
| `-i` | With `-p`, retain quoted protocol-variant sections during field extraction. |
| `-l` | Count calls grouped by record type, field 6, and a field-7 prefix; with `-d`, include disconnect reason. |
| `-j` | Time-disposition summary grouped by ACT fields appropriate to ATTEMPT or STOP. |
| `-q <n>` | Show the first *n* output records. |
| `-Q <n>` | Show the last *n* output records. |
| `-D` | Print diagnostic information. |
| `-h` | Display built-in help. |

Some combinations are intentionally disallowed: for example, `-p` cannot be used with `-l` or `-j`, and `-j` cannot be used with `-l`. Using `-j` or a nonzero `-d` without `-t` defaults to ATTEMPT records. Consult `./grepACT.sh -h` for additional option details.

## Usage examples

**Find a phone number in the latest ACT file:**

```bash
./grepACT.sh -s 4025551234
```

**Find STOP records from today:**

```bash
./grepACT.sh -t stop -y today -s 4025551234
```

**Search for either of two phone numbers across the latest three files:**

```bash
./grepACT.sh -f 3 -s 4025551234,7045554321
```

**Restrict a search to the called-number field:**

```bash
./grepACT.sh -t stop -o -s 4025551234
```

**Include one pattern while excluding another:**

```bash
./grepACT.sh -t attempt -s 4025551234 -z ROUTE_A -v TEST
```

**Investigate ATTEMPT disconnect reason 41 over a date range:**

```bash
./grepACT.sh -t attempt -d 41 -x 12/14/2025 -w 12/18/2025
```

**Find STOP records for emergency number 911:**

```bash
./grepACT.sh -t stop -e 911 -y today
```

**Count repeated field combinations:**

```bash
./grepACT.sh -t attempt -y today -p 1,6,12 -c
```

**Summarize call counts or time disposition:**

```bash
./grepACT.sh -t stop -l
./grepACT.sh -t attempt -j -y today
```

**Inspect only the first or last ten matches:**

```bash
./grepACT.sh -q 10 -s 4025551234
./grepACT.sh -Q 10 -s 4025551234
```

**Use the dedicated SALT extraction mode:**

```bash
./grepACT.sh -m
```

All phone numbers and route identifiers above are illustrative.

## How it works

For normal searches, grepACT uses a **streaming pipeline** of small Bash functions rather than assembling shell commands as strings:

```text
Select ACT files (date / count / recent)
                 |
Read plain or gzip-compressed records
                 |
Filter record type
                 |
Primary search -> additional include -> exclude
                 |
Emergency / disconnect-reason filters
                 |
ATTEMPT deduplication (optional)
                 |
Field extraction / count / time-disposition report
                 |
First or last N lines (optional)
                 |
Standard output
```

This separation makes the filtering and reporting stages easier to understand, test, and maintain. `read_act_files()` uses `cat` for plain ACT files and `gzip -cd` for compressed files. Reporting uses standard tools such as `awk`, `cut`, `sort`, and `uniq`.

### Security and reliability improvements

The refactored standard-search path **does not use `eval`** to execute dynamically constructed shell commands. Input is passed as quoted arguments or into explicit filter functions, reducing shell-injection risk. The script also validates several option values and combinations, uses `set -euo pipefail`, and cleans up temporary files when exiting.

These practices reduce risk; they are not a guarantee that every malformed input or operational edge case has been covered.

## SALT mode

SALT mode (`-m`) is a specialized extraction path intended for monitoring and alerting workflows. It selects recently modified ACT files (within approximately 35 minutes), gathers STOP and ATTEMPT records, removes repeated ATTEMPT records, and then applies timestamp filtering.

**Important:** The current implementation filters into a previous or current **half-hour reporting window**, depending on the minute at execution. It should not be described as an exact rolling 35-minute query. SALT mode must be used by itself; it does not accept the normal search and reporting flags alongside `-m`.

## Testing

The repository includes Bash regression tests under `tests/`, using **synthetic ACT records** rather than customer data. Coverage includes:

- Record-type and field-specific searches, include/exclude filtering, and emergency calls
- Disconnect-reason filtering and ATTEMPT deduplication
- Plain and gzip-compressed ACT files, including mixed-file searches
- Date selection and midnight rollover cases
- Field extraction (`-p`), counting (`-c`), and quoted-field handling (`-i`)
- Total call counts (`-l`) and time-disposition reporting (`-j`)
- Invalid inputs, safe file handling, and command-injection regression cases

Run the full local suite:

```bash
bash -n grepACT.sh
shellcheck grepACT.sh

for test in tests/test_*.sh; do
    bash "$test" || exit 1
done
```

Install [ShellCheck](https://www.shellcheck.net/) separately if it is not available. The repository also displays a GitHub Actions CI status badge; see `.github/workflows/ci.yml` for the exact checks run in CI.

## Operational notes and limitations

- Field positions are specific to the Ribbon / Sonus ACT record layout; verify the schema used by your SBC version.
- `-p` uses delimiter-based field extraction. Quoted sections affect the selected columns, and `-i` changes whether those sections are retained. This is not a general-purpose RFC 4180 CSV parser.
- Date searches rely on filesystem timestamps and the ACT rollover convention, not an independent parse of each record's date.
- `-d 0` currently means *no disconnect-reason filter*, not an explicit search for reason zero.
- Output includes a hostname and search-summary header in standard search mode.
- The tool is designed for investigation and operational use; validate behavior with representative data before integrating it into production automation.

## Data and privacy

This repository is intended to contain **no customer call records or proprietary production data**. Documentation examples use sanitized numbers and generic identifiers; regression tests use generated test data.

## Author

**Calvin Nielsen**
