# grepACT

`grepACT.sh` is a Bash utility for querying Ribbon / Sonus SBC ACT (CDR) files at scale.
It supports advanced filtering, date-based file selection, deduplication, and summary reporting
across both plain and gzipped ACT files.

This script was developed and used in a Tier-1 enterprise voice environment supporting high-volume SIP traffic.

---

## Features

- Supports START / STOP / ATTEMPT CDRs
- Searches across rolled ACT files (plain + `.gz`)
- Date, range, and rolling window searches
- Emergency call detection (911 / 933)
- Disconnect-reason analytics
- Call deduplication logic for retries
- SALT mode for monitoring/alerting (last ~35 minutes of traffic)
- Field extraction with optional protocol details
- Designed for large datasets (millions of CDRs)

---

## Requirements

- Bash 4+
- GNU coreutils
- awk, grep, sed, cut, sort, uniq
- zcat (for compressed ACT files)
- Linux environment with access to the SBC evlog directory

Operational assumptions:
- ACT files roll at **00:00:00 UTC/GMT**
- Script is typically run from the `linuxadmin` user context and requires read access to the evlog directory

---

## Installation

Run the following commands from a Linux system with access to the SBC evlog directory.
```bash
git clone https://github.com/<your-username>/grepACT.git
cd grepACT
chmod +x grepACT.sh
```

---

## Basic Usage

Search the most recent ACT file:
```bash
./grepACT.sh -s 4025551234
```

Search STOP CDRs from today:
```bash
./grepACT.sh -t stop -y today -s 4025551234
```

Search ATTEMPT CDRs with DR=41 over a date range:
```bash
./grepACT.sh -t attempt -d 41 -x 12/14/2025 -w 12/18/2025
```

---

## SALT Mode

SALT mode is intended for monitoring and alerting. It extracts the last
~35 minutes of STOP and ATTEMPT CDRs to help detect spikes in call failures,
drops, or potential media-quality symptoms.
```bash
./grepACT.sh -m
```

⚠️ SALT mode must be run alone (no additional flags).

---

## Notes

- Script is read-only; no files are modified
- Field positions align with Ribbon SBC CDR formats
- Designed for use in operational troubleshooting and proactive monitoring

---

## Disclaimer

This repository contains **no customer data**.

All examples use sanitized phone numbers and generic identifiers.

---

## Author

Calvin Nielsen