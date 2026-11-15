#!/bin/bash

############################
# Script Name  : grepACT.sh
# Purpose      : Query Ribbon/Sonus SBC ACT (CDR) files and print results based on user options
#
# Designed for large-scale SBC environments (millions of CDRs/day)
#
# Requirements :
#   - ACT files must roll at midnight GMT to match CDR timing.
#   - Script must be executable.
#   - /home/log/sonus/sbx/evlog/ must be accessible by linuxadmin.
#   - Script should reside in /home/linuxadmin/ directory.
#
# Change Log
#   V1.00 : Initial release (see grepACT_old for previous updates)
#   V2.00 : Rebuilt to clean up unused options
#   V3.00 : Improved portability and relevance across enterprises
#
# Notes
#   - For troubleshooting, use -D to print debug lines and/or -q (head) or -Q (tail) to limit output lines.
#   - Supports both plain and gzipped ACT files.
#   - For support, contact Calvin Nielsen.
############################

# Error handling
set -euo pipefail
trap 'echo "ERROR: Script failed at line $LINENO" >&2' ERR
trap '' PIPE

# Script debugging
DEBUG=0

# Create a temp file for CDR storage and processing
cdr_tmpfile=$(mktemp)
filtered_cdr_tmpfile=$(mktemp)
trap 'rm -f "$cdr_tmpfile" "$filtered_cdr_tmpfile"' EXIT

#----------------------------
# Default variables
#----------------------------
evlog_dir="${GREPACT_EVLOG_DIR:-/var/log/sonus/sbx/evlog/}"
sbc_hostname=$(hostname)
bn=$(basename "$0")
five_days_ago=$(TZ=GMT date -d "5 days ago" +"%m/%d/%Y")
min=$(TZ=GMT date +%M)
hour=$(TZ=GMT date +%H)
# get previous hour for SALT CDR checks
if [[ $hour == "00" ]]; then
    prehour=23
else
    prehour=$(TZ=GMT+1 date +%H)
fi

numfiles=1          # -f
recordtype=""       # -t (START|STOP|ATTEMPT), empty => all
search=""           # -s
add_search=""       # -z (additional include)
exclude=""          # -v (exclude)
dr="0"              # -d disconnect reason
printfields=""      # -p fields list
printcount="0"      # -c
rem_dup="0"         # -u
prot_varnt_dis="0"  # -i
daymode=""          # -y today|yest|week
search_date=""      # -x MM/DD/YYYY
end_search_date=""  # -w MM/DD/YYYY
salt_run="0"        # -m
timedisposition="0" # -j (4)
total_call_ct="0"   # -l
search_calling="0"  # -n
search_called="0"   # -o
emergency=""        # -e (911 or 933)
quicklines=0        # -q (quick lines - n number of lines to return)
quickcmd="head"     # -Q (tails/heads the returned results)

# ----------------------------
# Helpers
# ----------------------------
die() { 
    set +e
    trap - ERR
    echo "ERROR: $1" >&2
    exit "${2:-1}"
}
warn() { echo "WARN: $*" >&2; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required dependency: $1" 127; }
is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

# Read plain and compressed ACT files without eval.
read_act_files() {
    local file

    for file in "$@"; do
        if [[ "$file" == *.gz ]]; then
            gzip -cd -- "$file"
        else
            cat -- "$file"
        fi
    done
}

# Filter ACT records by record type.
filter_record_type() {
    awk -F, -v type="$recordtype" '
        type == "" {
            if ($1 == "START" || $1 == "STOP" || $1 == "ATTEMPT")
                print
            next
        }
        $1 == type { print }
    '
}

# Apply the primary -s search filter directly.
filter_search() {
    if [[ -z "$search" ]]; then
        cat
        return
    fi

    if [[ "$search_calling" == 1 || "$search_called" == 1 ]]; then
        GREPACT_PATTERN="$search" \
            awk -F, -v field="$search_field" '
                BEGIN { pattern = ENVIRON["GREPACT_PATTERN"] }
                $field ~ pattern { print }
            '
    else
        grep -Ei -- "$search"
    fi
}

# Apply the additional -z search filter.
filter_additional_search() {
    if [[ -z "$add_search" ]]; then
        cat
    else
        grep -Ei -- "$add_search"
    fi
}

# Exclude records matching the -v search pattern.
filter_exclude_search() {
    if [[ -z "$exclude" ]]; then
        cat
    else
        grep -Eiv -- "$exclude"
    fi
}

# Filter emergency calls using the appropriate ACT field.
filter_emergency() {
    local field

    if [[ "$emergency" != "911" && "$emergency" != "933" ]]; then
        cat
        return
    fi

    case "$recordtype" in
        START)   field=16 ;;
        STOP)    field=21 ;;
        ATTEMPT) field=18 ;;
        *)       cat; return ;;
    esac

    awk -F, -v field="$field" -v number="$emergency" '
        $field == number { print }
    '
}

# Filter ACT records by disconnect reason (-d).
filter_disconnect_reason() {
    local field

    if [[ "$dr" == "0" ]]; then
        cat
        return
    fi

    case "$recordtype" in
        STOP)    field=15 ;;
        ATTEMPT) field=12 ;;
        *)       cat; return ;;
    esac

    awk -F, -v field="$field" -v reason="$dr" '
        $field == reason { print }
    '
}

# Remove duplicate ATTEMPT records (-u).
filter_duplicates() {
    if [[ "$rem_dup" != "1" ]]; then
        cat
        return
    fi

    awk -F, '!a[$6 substr($10,1,5) $17 $18]++'
}

# Print selected ACT fields (-p), optionally counting occurrences (-c).
# Preserve quoted sections when -i is specified.
filter_print_fields() {
    if [[ -z "$printfields" ]]; then
        cat
        return
    fi

    if [[ "$prot_varnt_dis" == "1" ]]; then
        if [[ "$printcount" == "1" ]]; then
            cut -d'"' -f1,2,3,4,5,6,7,8,9- |
                cut -d, -f"$printfields" |
                sort |
                uniq -c |
                sed 's/,/ /g'
        else
            cut -d'"' -f1,2,3,4,5,6,7,8,9- |
                cut -d, -f"$printfields" |
                sed 's/,/ /g'
        fi
    else
        if [[ "$printcount" == "1" ]]; then
            cut -d'"' -f1,3,5,7,9- |
                cut -d, -f"$printfields" |
                sort |
                uniq -c |
                sed 's/,/ /g'
        else
            cut -d'"' -f1,3,5,7,9- |
                cut -d, -f"$printfields" |
                sed 's/,/ /g'
        fi
    fi
}

# Generate total call counts (-l), optionally grouped by disconnect reason.
filter_total_call_counts() {
    if [[ "$total_call_ct" != "1" ]]; then
        cat
        return
    fi

    if [[ "$dr" != "0" ]]; then
        case "$recordtype" in
            ATTEMPT)
                awk -F, '{print $1,$6,substr($7,1,4),$12}'
                ;;
            STOP)
                awk -F, '{print $1,$6,substr($7,1,4),$15}'
                ;;
            *)
                cat
                return
                ;;
        esac
    else
        awk -F, '{print $1,$6,substr($7,1,4)}'
    fi | sort | uniq -c | sed 's/,/ /g'
}

# Generate time-disposition counts (-j).
filter_time_disposition() {
    if [[ "$timedisposition" != "4" ]]; then
        cat
        return
    fi

    case "$recordtype" in
        ATTEMPT)
            awk -F, '{print $6,substr($10,1,4),$12}'
            ;;
        STOP)
            awk -F, '{print $6,substr($12,1,4),$15}'
            ;;
        *)
            cat
            return
            ;;
    esac | sort | uniq -c | sed 's/,/ /g'
}

select_act_files() {
    local mode="${1:-}"
    local arg1="${2:-}"
    local arg2="${3:-}"
    local files=()
    if [[ "$DEBUG" == "1" ]]; then
        echo "DEBUG: [select_act_files] called with: $mode $arg1 $arg2" >&2
    fi

    case "$mode" in
        salt)
            mapfile -t files < <(find "$evlog_dir" -maxdepth 1 -type f -mmin -35 -name "*[0123456789ABCDEF][0123456789ABCDEF][0123456789ABCDEF][0123456789ABCDEF].ACT" ! -name "*.gz")
            if [[ "$DEBUG" == "1" ]]; then
                echo "DEBUG: [salt] Final files to return: ${files[*]}" >&2
            fi
            ;;
        date)
            local search_start search_end search_end_plus1
            search_start=$(date -d "$arg1" +"%Y-%m-%d 00:00:00") || die "Invalid search_date: $arg1" 64
            search_end=$(date -d "$arg1 +1 day" +"%Y-%m-%d 00:00:00") || die "Invalid search_date: $arg1" 64
            search_end_plus1=$(date -d "$arg1 +2 day" +"%Y-%m-%d 00:00:00") || die "Invalid search_date: $arg1" 64

            # Get all files for the search date, sorted by time (include timestamp for filtering)
            mapfile -t files_with_time < <(find "$evlog_dir" -maxdepth 1 -type f \( -name "*.ACT" -o -name "*.ACT.gz" \) \
                -newermt "$search_start" ! -newermt "$search_end" -printf "%T@ %f\n" | sort -n)

            files=()
            for entry in "${files_with_time[@]}"; do
                ts_epoch="${entry%% *}"
                fname="${entry#* }"
                # Convert epoch to HH:MM:SS
                file_time=$(date -d @"${ts_epoch%.*}" +"%H:%M:%S")
                # Drop file if created at 00:00:00
                if [[ ${#files[@]} -eq 0 && "$file_time" == "00:00:00" ]]; then
                    if [[ "$DEBUG" == "1" ]]; then
                        echo "DEBUG: [date] Dropping $fname created at $file_time" >&2
                    fi
                    continue
                fi
                files+=("$fname")
            done
            if [[ "$DEBUG" == "1" ]]; then
                echo "DEBUG: [date] After drop: ${files[*]}" >&2
            fi

            # Find the next day's file created at 00:00:00
            mapfile -t next_file_entry < <(find "$evlog_dir" -maxdepth 1 -type f \( -name "*.ACT" -o -name "*.ACT.gz" \) \
                -newermt "$search_end" ! -newermt "$search_end_plus1" -printf "%T@ %f\n" | sort -n)
            for entry in "${next_file_entry[@]}"; do
                ts_epoch="${entry%% *}"
                fname="${entry#* }"
                file_time=$(date -d @"${ts_epoch%.*}" +"%H:%M:%S")
                if [[ "$file_time" == "00:00:00" ]]; then
                    if [[ "$DEBUG" == "1" ]]; then
                        echo "DEBUG: [date] Appending next day's file: $fname created at $file_time" >&2
                    fi
                    files+=("$fname")
                    break
                fi
            done

            if [[ "$DEBUG" == "1" ]]; then
                echo "DEBUG: [date] Final files to return: ${files[*]}" >&2
            fi
            printf '%s\n' "${files[@]}"
            if [[ "$DEBUG" == "1" ]]; then
                echo "DEBUG: [date] select_act_files finished" >&2
            fi
            ;;

        range)
            local search_start search_end search_end_plus1
            search_start=$(date -d "$arg1" +"%Y-%m-%d 00:00:00") || die "Invalid search_date: $arg1" 64
            search_end=$(date -d "$arg2" +"%Y-%m-%d 00:00:00") || die "Invalid end_search_date: $arg2" 64
            search_end_plus1=$(date -d "$arg2 +1 day" +"%Y-%m-%d 00:00:00") || die "Invalid end_search_date: $arg2" 64

            if [[ "$DEBUG" == "1" ]]; then
                echo "DEBUG: [range] search_start: $search_start search_end: $search_end search_end_plus1: $search_end_plus1" >&2
            fi

            # Get all files in the range
            mapfile -t files_with_time < <(
                find "$evlog_dir" -maxdepth 1 -type f \( -name "*.ACT" -o -name "*.ACT.gz" \) \
                    -newermt "$search_start" ! -newermt "$search_end_plus1" -printf "%T@ %f\n" | sort -n
            )

            if [[ "$DEBUG" == "1" ]]; then
                printf "DEBUG: [range] files_with_time:\n%s\n" "${files_with_time[@]}" >&2
            fi

            files=()
            first_entry=1
            for entry in "${files_with_time[@]}"; do
                ts_epoch="${entry%% *}"
                fname="${entry#* }"
                file_time=$(date -d @"${ts_epoch%.*}" +"%H:%M:%S")
                # Only skip the very first file if it was created at midnight
                if [[ $first_entry -eq 1 && "$file_time" == "00:00:00" ]]; then
                    if [[ "$DEBUG" == "1" ]]; then
                        echo "DEBUG: [range] Skipping $fname created at $file_time" >&2
                    fi
                    first_entry=0
                    continue
                fi
                files+=("$fname")
                first_entry=0
            done
            
            # Find the first file at midnight on the day after the end date
            search_end_date=$(date -d "$search_end" +"%Y-%m-%d")
            search_end_plus1_date=$(date -d "$search_end_plus1" +"%Y-%m-%d")
            midnight_lower="${search_end_date} 23:59:59"
            midnight_upper="${search_end_plus1_date} 00:00:01"
            midnight_file_entry=$(find "$evlog_dir" -maxdepth 1 -type f \( -name "*.ACT" -o -name "*.ACT.gz" \) \
                -newermt "$midnight_lower" ! -newermt "$midnight_upper" -printf "%T@ %f\n" | sort -n | head -1)
            if [[ -n "$midnight_file_entry" ]]; then
                midnight_fname="${midnight_file_entry#* }"
                # Check whether the midnight file is already in the array
                file_exists=0

                for existing_file in "${files[@]}"; do
                    if [[ "$existing_file" == "$midnight_fname" ]]; then
                        file_exists=1
                        break
                    fi
                done

                if [[ $file_exists -eq 0 ]]; then
                    files+=("$midnight_fname")
                    if [[ "$DEBUG" == "1" ]]; then
                        echo "DEBUG: [range] Appending midnight file: $midnight_fname" >&2
                    fi
                fi
            fi

            if [[ "$DEBUG" == "1" ]]; then
                echo "DEBUG: [range] Final files to return: ${files[*]}" >&2
            fi
            printf '%s\n' "${files[@]}"
            ;;
        today)
            local today_start
            today_start=$(date -d "today 00:00" +"%Y-%m-%d %H:%M:%S")
            mapfile -t files < <(find "$evlog_dir" -maxdepth 1 -type f \( -name "*.ACT" -o -name "*.ACT.gz" \) -newermt "$today_start" -printf "%T@ %f\n" | sort -n | tail -n +2 | awk '{print $2}')
            if [[ "$DEBUG" == "1" ]]; then
                echo "DEBUG: [today] select_act_files finished" >&2
            fi
            ;;
        yest)
            local yest_start yest_end first_today_file
            yest_start=$(date -d "yesterday 00:00" +"%Y-%m-%d %H:%M:%S")
            yest_end=$(date -d "today 00:00" +"%Y-%m-%d %H:%M:%S")
            mapfile -t files < <(find "$evlog_dir" -maxdepth 1 -type f \( -name "*.ACT" -o -name "*.ACT.gz" \) -newermt "$yest_start" ! -newermt "$yest_end" -printf "%T@ %f\n" | sort -n | tail -n +2 | awk '{print $2}')
            first_today_file=$(find "$evlog_dir" -maxdepth 1 -type f \( -name "*.ACT" -o -name "*.ACT.gz" \) -newermt "$yest_end" -printf "%T@ %f\n" | sort -n | head -1 | awk '{print $2}')
            if [[ -n "$first_today_file" ]]; then
                files+=("$first_today_file")
            fi

            if [[ "$DEBUG" == "1" ]]; then
                echo "DEBUG: [yest] select_act_files finished" >&2
            fi
            ;;
        week)
            mapfile -t files < <(find "$evlog_dir" -maxdepth 1 -type f \( -name "*.ACT" -o -name "*.ACT.gz" \) -mtime -7 -printf "%T@ %f\n" | sort -n | tail -n +1 | awk '{print $2}')
            if [[ "$DEBUG" == "1" ]]; then
                echo "DEBUG: [week] select_act_files finished" >&2
            fi
            ;;
        numfiles)
            mapfile -t files < <(find "$evlog_dir" -maxdepth 1 -type f \( -name "*.ACT" -o -name "*.ACT.gz" \) | sort | tail -n "$arg1")
            if [[ "$DEBUG" == "1" ]]; then
                echo "DEBUG: [numfiles] select_act_files finished" >&2
            fi
            ;;
        last)
            mapfile -t files < <(find "$evlog_dir" -maxdepth 1 -type f \( -name "*.ACT" -o -name "*.ACT.gz" \) | sort | tail -n 1)
            if [[ "$DEBUG" == "1" ]]; then
                echo "DEBUG: [last] select_act_files finished" >&2
            fi
            ;;
    esac
    printf '%s\n' "${files[@]}"
}

usage() {
    cat <<USAGE
grepACT - query Ribbon/Sonus SBC ACT (CDR) files

Usage:
    $bn [options]

ACT file selection:
    -f <n>           Number of files to search (default: 1)
    -y <today|yest|week>
                    Search ACT files written today, yesterday, or in the last 7 days
    -x <MM/DD/YYYY>  Search ACT files written on a specific date
    -w <MM/DD/YYYY>  End date for a range search (requires -x)
    -m               SALT mode: pull last ~35 minutes of CDRs (no other flags allowed)

Record selection:  
    -t <start|stop|attempt>
                        Record type to search (default: all)
    -s <pattern>     Search pattern (regex, case-insensitive). Comma-separated = OR.
    -z <pattern>     Additional include filter (regex)
    -v <pattern>     Exclude filter (regex)
    -e <911|933>     Emergency filter (called number)
    -d <dr>          Disconnect reason (ATTEMPT uses field 12; STOP uses field 15)
    -u               Remove duplicate calls (ATTEMPT only)
    -n               With -s: match calling-number field (STOP/ATTEMPT only)
    -o               With -s: match called-number field (STOP/ATTEMPT only)

Debugging:
    -D              Enable debug output
    -q <n>          Quick output: print first n lines
    -Q <n>          Quick output: print last n lines

Output shaping:
    -p <fields>      Print specific CSV fields (comma list, e.g. 1,6,7)
    -c               With -p: count unique lines (sort | uniq -c)
    -i               Include ingress/egress protocol variant fields in parsing
    -j               Time disposition report (cannot be used with -p)
    -l               Total call count report
    -h               Help

Notes:
    - Date format for -x and -w is MM/DD/YYYY.
    - Field numbers for -p are 1-based and refer to CSV columns.
    - By default, quoted fields (e.g., calling name, protocol variant data) are removed when printing fields with -p,
      to match Ribbon CDR mapping. Use -i to keep quoted details in the output.

Examples:
    $bn -s 4025551234
        # Search for 4025551234 in the latest ACT file (all record types)
    
    $bn -s 4025551234,7045554321
        # Search for 4025551234 OR 7045554321 in the latest ACT file (all record types)
    
    $bn -s 4025551234 -f 2
        # Search for 4025551234 in the last 2 ACT files
    
    $bn -s 4025551234 -y today -t stop -p 1,6,7
        # Today's STOP CDRs for 4025551234, print and count fields 1(CDR Type), 6(Start Date) and 7(Start Time)

    $bn -s 4025551234 -x 12/14/2025 -w 12/18/2025 -t attempt -d 41 -p 1,29,31 -c
        # attempt CDRs with DR41 from 12/14/25 to 12/18/25, count and print fields 1(CDR Type), 29(Route Label), 31(Route Selected)
    
    $bn -t attempt -y today -p1,6,12 -c
        # Today's ATTEMPT CDRs, count and print fields 1(CDR Type), 6(Start Date) and 12(Disconnect Reason)
    
    $bn -t attempt -y yest -s W2 -p1,26,28 -c
        # Yesterday's ATTEMPT CDRs for W2, count and print fields 1(CDR Type), 26(Route Label) and 28(Route Selected)

    $bn -t stop -s 4025551234 -y week -p1,20,21,29,31 -c
        # STOP CDRs for 4025551234 in the past week, count and print fields 1(CDR Type), 20(Calling #), 21 (Called #), 29(Route Label), 31(Route Selected)
    
    $bn -t attempt -d 1 -x $five_days_ago -p1,12,26,2,8 -c
        # ATTEMPT CDRs with DR1 from the provided search date, count and print fields 1(CDR Type), 12(Disconnect Reason), 26(Route Label) and 28(Route Selected)

    $bn -q 10 -s 4025551234
        #show the first 10 match lines for 4025551234 (Search in last ACT file and all record types)
     
    $bn -Q 10 -s 4025551234
        #show the last 10 match lines for 4025551234 (Search in last ACT file and all record types)

    $bn -d 1 -j -c -y today
        # Todays ATTEMPT CDRs with DR1, time disposition report, count by 10-min interval (Record Type set to ATTEMPT by default when not defined)

    $bn -h
        # Show this help message

For more details, see script header or contact Calvin Nielsen(calvin.nielsen@outlook.com)
USAGE
}

# ----------------------------
# Parse CLI
# ----------------------------
while getopts ":t:f:s:z:v:e:p:culmnoiy:Dd:x:w:jhq:Q:" opt; do
    case "$opt" in
        D) DEBUG="1" ;;
        t) recordtype="$(echo "$OPTARG" | tr '[:lower:]' '[:upper:]')" ;;
        f) is_uint "$OPTARG" || die "-f requires a numeric value: $OPTARG" 64; numfiles="$OPTARG" ;;
        s) search="$OPTARG" ;;
        z) add_search="$OPTARG" ;;
        v) exclude="$OPTARG" ;;
        e) emergency="$OPTARG" ;;
        p) printfields="$OPTARG" ;;
        q) quicklines="$OPTARG" ;;
        Q) quickcmd="tail"; quicklines="$OPTARG" ;;
        c) printcount="1" ;;
        u) rem_dup="1" ;;
        l) total_call_ct="1" ;;
        m) salt_run="1" ;;
        n) search_calling="1" ;;
        o) search_called="1" ;;
        i) prot_varnt_dis="1" ;;
        y) daymode="$(echo "$OPTARG" | tr '[:lower:]' '[:upper:]')" ;;
        d) dr="$OPTARG" ;;
        x) search_date="$OPTARG" ;;
        w) end_search_date="$OPTARG" ;;
        j) timedisposition="4" ;;
        h) usage; exit 0 ;;
       \?) usage; exit 1 ;;
    esac
done

# ----------------------------
# Dependencies + validation
# ----------------------------
need_cmd awk; need_cmd grep; need_cmd find; need_cmd date; need_cmd sort; need_cmd uniq; need_cmd cut

# Check if evlog directory exists, verifies if SBC is currently active
if [[ ! -d "$evlog_dir" ]]; then
    die "$evlog_dir directory not found: $sbc_hostname is likely not active" 66
fi

# Check if Record Type is set and with START, STOP or ATTEMPT only
if [[ -n "$recordtype" ]] && [[ "$recordtype" != "START" && "$recordtype" != "STOP" && "$recordtype" != "ATTEMPT" ]]; then
    die "Invalid -t value. Use start, stop, or attempt." 64
fi

# Check if Emergency flag was provided and 911 or 933 arguement provided
if [[ -n "$emergency" ]]; then
    [[ "$recordtype" == "START" || "$recordtype" == "STOP" || "$recordtype" == "ATTEMPT" ]] || die "Option -e requires -t start|stop|attempt." 64
    [[ "$emergency" == "911" || "$emergency" == "933" ]] || die "Option -e must be 911 or 933." 64
fi

# exit if search_calling and search_called are passed without -s search string and -t record type
if [[ "$search_calling" == "1" || "$search_called" == "1" ]]; then
    [[ -n "$search" ]] || die "Options -n/-o require -s <pattern>." 64
    [[ "$recordtype" == "STOP" || "$recordtype" == "ATTEMPT" ]] || die "Options -n/-o require -t stop or -t attempt." 64
fi

# exit if remove duplicate and STOP recordtype is chosen
if [[ "$rem_dup" == "1" && "$recordtype" == "STOP" ]]; then
    die "Option -u (remove duplicates) is ATTEMPT-only. Do not use with -t stop." 64
fi

# Validate search_date format if provided
if [[ -n "$search_date" ]]; then
    if ! [[ "$search_date" =~ ^(0[1-9]|1[0-2])/(0[1-9]|[12][0-9]|3[01])/[0-9]{4}$ ]]; then
        die "Invalid date format for -x (search_date): \"$search_date\". Use MM/DD/YYYY." 64
    fi
fi

# Check user entered a start date with -x when entering an end date with -w
if [[ -n "$end_search_date" && -z "$search_date" ]]; then
    if ! [[ "$end_search_date" =~ ^(0[1-9]|1[0-2])/(0[1-9]|[12][0-9]|3[01])/[0-9]{4}$ ]]; then
        die "Invalid date format for -w (end_search_date): \"$end_search_date\". Use MM/DD/YYYY." 64
    else
        die "Option -w requires -x (start_date)." 64
    fi
fi

# Validate printfields and timedisposition
if [[ -n "$printfields" && "$timedisposition" == "4" ]]; then
    die "Cannot use -p with -j." 64
fi

# Validate that only one of -x, -y, or -f is used at a time
if { [[ -n "$search_date" ]] && [[ -n "$daymode" ]]; } || \
    { [[ -n "$search_date" ]] && [[ "$numfiles" != "1" ]]; } || \
    { [[ -n "$daymode" ]] && [[ "$numfiles" != "1" ]]; }; then
        die "Options -x (search_date), -y (daymode), and -f (numfiles) are mutually exclusive. Use only one at a time." 64
fi

# Check if daymode is set and valid with "today", "yest", or "week"
if [[ -n "$daymode" ]]; then
    if [[ "$daymode" != "TODAY" && "$daymode" != "YEST" && "$daymode" != "WEEK" ]]; then
        die "Did not enter a valid option with \"-y\", enter today, yest or week" 64
    fi
fi

# If running -j or -d without -t, default to ATTEMPT
if [[ -z "$recordtype" ]] && { [[ "$timedisposition" == "4" ]] || [[ "$dr" != "0" ]]; }; then
    recordtype="ATTEMPT"
fi

# Validate user does not use -p with -l
if [[ -n "$printfields" && "$total_call_ct" == "1" ]]; then
    die "Options -p (printfields) and -l (total_call_ct) are mutually exclusive. Use only one at a time." 64
fi

# Validate users only uses -c with -p or -j (timedisposition)
if [[ "$printcount" == "1" && -z "$printfields" && "$timedisposition" != "4" ]]; then
    die "Option -c (count) requires -p (printfields) or -j (timedisposition)." 64
fi

# Validate -i flag (prot_varnt_dis) is used with -p (printcount)
if [[ "$prot_varnt_dis" == "1" && -z "$printcount" ]]; then
    die "Option -i (prot_varnt_dis) requires -p (printcount)." 64
fi

# ----------------------------
# GET ACT Files from evlog directory
# ----------------------------

## Check for SALT run to get ACT files from the last 35 minutes, verify no other options
if [[ "$salt_run" == "1" ]]; then
    other_flags=0
    [[ -n "$search_date" ]] && ((++other_flags))
    [[ -n "$daymode" ]] && ((++other_flags))
    [[ -n "$search" ]] && ((++other_flags))
    [[ -n "$add_search" ]] && ((++other_flags))
    [[ -n "$exclude" ]] && ((++other_flags))
    [[ -n "$emergency" ]] && ((++other_flags))
    [[ "$total_call_ct" == "1" ]] && ((++other_flags))
    [[ "$dr" != "0" ]] && ((++other_flags))
    [[ "$rem_dup" == "1" ]] && ((++other_flags))
    [[ "$timedisposition" == "4" ]] && ((++other_flags))
    [[ -n "$printfields" ]] && ((++other_flags))
    [[ -n "$recordtype" ]] && ((++other_flags))
    [[ "$printcount" == "1" ]] && ((++other_flags))
    [[ "$search_calling" == "1" ]] && ((++other_flags))
    [[ "$search_called" == "1" ]] && ((++other_flags))
    [[ "$prot_varnt_dis" == "1" ]] && ((++other_flags))
    [[ "$numfiles" != "1" ]] && ((++other_flags))
    [[ -n "$end_search_date" ]] && ((++other_flags))

    if (( other_flags > 0 )); then
        die "SALT mode (-m) Must be run without other options." 64
    else
        mapfile -t act_files < <(select_act_files salt)
        if [[ "$DEBUG" == "1" ]]; then
            echo "act_files: ${act_files[*]}"
        fi
    fi
# if only -x was passed for specific date
elif [[ -n "$search_date" ]] && [[ -z "$end_search_date" ]]; then
    mapfile -t act_files < <(select_act_files date "$search_date")

# if -x and -w were provided to search a date range
elif [[ -n "$search_date" ]] && [[ -n "$end_search_date" ]]; then
    mapfile -t act_files < <(select_act_files range "$search_date" "$end_search_date")

# Get ACT files for today's date
elif [[ "$daymode" == "TODAY" ]]; then
    mapfile -t act_files < <(select_act_files today)

# Get ACT files for Yesterday's date
elif [[ "$daymode" == "YEST" ]]; then
    mapfile -t act_files < <(select_act_files yest)

# Get ACT files for the past 7 days
elif [[ "$daymode" == "WEEK" ]]; then
    mapfile -t act_files < <(select_act_files week)

# Get last x number of files based on -f numfiles flag
elif [[ "$numfiles" -gt 1 ]]; then
    mapfile -t act_files < <(select_act_files numfiles "$numfiles")

# get last written ACT file
else
    mapfile -t act_files < <(select_act_files last)
fi

# Remove Duplicate act_files
mapfile -t act_files < <(printf "%s\n" "${act_files[@]}" | awk '!seen[$0]++')

if [[ "$DEBUG" == "1" ]]; then
    echo "DEBUG: act_files: ${act_files[*]}"
fi

### Count number of ACT files and split the zipped and non-zipped files into separate variables
files_searched="${#act_files[@]}"
act_files_gz=()
act_files_non_gz=()
for file in "${act_files[@]}"; do
    if [[ "$file" == *.gz ]]; then
        act_files_gz+=("$file")
    else
        act_files_non_gz+=("$file")
    fi
done

# No ACT files found, exit
if (( files_searched == 0 )); then
    die "No ACT files found with the option(s) provided, verify option(s) format" 66
fi

## specific to SALT run only, pull CDRs for the past 35 minutes and exits
if [[ "$salt_run" == "1" ]]; then
    if [[ "${#act_files[@]}" -eq 0 ]]; then
        die "No ACT files found in the last 35 minutes for SALT mode." 66
    else
        #sort ACT files array
        mapfile -t sorted < <(printf "%s\n" "${act_files[@]}" | sort)
        act_files=("${sorted[@]}")
    fi

    if (( 10#$min <= 29 )); then
        start_time="${prehour}:30:00.0"
        end_time="${prehour}:59:59.9"

        if [[ "$DEBUG" == "1" ]]; then
            echo "DEBUG: Top of hour - $start_time $end_time"
        fi
        for act_file in "${act_files[@]}"; do
            if [[ "$DEBUG" == "1" ]]; then
                echo "DEBUG: ACT File: $act_file"
            fi
            grep "$prehour:[345][0123456789]:[0123456789][0123456789].[0123456789]" "$act_file" >> "$cdr_tmpfile" || true
        done
    else
        start_time="${hour}:00:00.0"
        end_time="${hour}:29:59.9"

        if [[ "$DEBUG" == "1" ]]; then
            echo "DEBUG: Bottom of hour - $start_time $end_time"
        fi

        for act_file in "${act_files[@]}"; do
            if [[ "$DEBUG" == "1" ]]; then
                echo "DEBUG: ACT File: $act_file"
            fi
            grep "$hour:[012][0123456789]:[0123456789][0123456789].[0123456789]" "$act_file" >> "$cdr_tmpfile" || true
        done
    fi

    # Pull STOP and ATTEMPT CDRs, remove repeating CDRs for calls retrying and generating multiple ATTEMPTs in a single dialog
    grep STOP "$cdr_tmpfile" > "$filtered_cdr_tmpfile"
    grep ATTEMPT "$cdr_tmpfile" | awk -F, '!a[$6substr($10,1,5)$17,$18]++' >> "$filtered_cdr_tmpfile"

    while read -r line; do
        cdr_type=$(echo "$line" | cut -d, -f1)
        if [[ "$cdr_type" == "STOP" ]]; then
            timestamp=$(echo "$line" | cut -d, -f12)
        elif [[ "$cdr_type" == "ATTEMPT" ]]; then
            timestamp=$(echo "$line" | cut -d, -f10)
        else
            timestamp=""
        fi
        # Only proceed if timestamp is set
        if [[ -n "$timestamp" ]]; then
            # Validate timestamp format (should be HH:MM:SS or similar)
            if [[ "$timestamp" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?$ ]]; then
                if (( 10#$min <= 29 )); then
                    start_time="${prehour}:30:00.0"
                    end_time="${prehour}:59:59.9"
                else
                    start_time="${hour}:00:00.0"
                    end_time="${hour}:29:59.9"
                fi
                set +e
                ts_epoch=$(date -d "1970-01-01 $timestamp" +%s 2>/dev/null)
                start_epoch=$(date -d "1970-01-01 $start_time" +%s 2>/dev/null)
                end_epoch=$(date -d "1970-01-01 $end_time" +%s 2>/dev/null)

                if [[ "$DEBUG" == "1" ]]; then
                    echo "DEBUG: $start_epoch $ts_epoch $end_epoch"
                fi

                set -e 
                if [[ -n "$ts_epoch" && -n "$start_epoch" && -n "$end_epoch" ]]; then
                    if [[ "$ts_epoch" -ge "$start_epoch" && "$ts_epoch" -le "$end_epoch" ]]; then
                        echo "$line"
                    fi
                fi
            else
                warn "Skipping line with invalid timestamp: '$timestamp'"
            fi
        fi
    done < "$filtered_cdr_tmpfile"

    exit 0
fi

# Validate search and reporting options.
if [[ -n "$search" ]]; then
    # replace . with \. to comment out a period if user enters one
    search="${search//./\\.}"

    # check if user entered 2 search parameters using a comma, replace comma with pipe to use with grep command, allow "OR" search logic
    if [[ "$search" == *,* ]]; then
        search="${search//,/|}"
        # check if user entered in -n or -o, die if so
        if [[ "$search_calling" == 1 || "$search_called" == 1 ]]; then
            die "Invalid search parameters: -n or -o cannot be used with multiple search terms" 64
        fi
    fi

    if [[ "$search_calling" == 1 || "$search_called" == 1 ]]; then
        # Select the correct ACT field based on record type.
        if [[ "$search_calling" == 1 ]]; then
            case "$recordtype" in
                START)   search_field=15 ;;
                ATTEMPT) search_field=17 ;;
                STOP)    search_field=20 ;;
            esac
        else
            case "$recordtype" in
                START)   search_field=16 ;;
                ATTEMPT) search_field=18 ;;
                STOP)    search_field=21 ;;
            esac
        fi
    fi
fi

# -z additional search string.
if [[ -n "$add_search" ]]; then
    add_search="${add_search//./\\.}"
fi

# -v exclude search string.
if [[ -n "$exclude" ]]; then
    exclude="${exclude//./\\.}"
fi

# Disconnect Reason must be a non-negative integer.
if ! [[ "$dr" =~ ^[0-9]+$ ]]; then
    die "Option -d requires a non-negative integer." 64
fi

# Validate -p field selection.
# Accept numbers, comma-separated lists, and numeric ranges.
if [[ -n "$printfields" ]]; then
    if ! [[ "$printfields" =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]]; then
        die "Option -p requires field numbers or ranges (example: 1,6-10,15)." 64
    fi
fi

# -d validation for unsupported record types.
if [[ "$dr" != 0 ]]; then
    if [[ "$recordtype" == "START" ]]; then
        die "No Disconnect Reason within a START CDR, use -t stop or -t attempt" 64
    elif [[ -z "$recordtype" && "$total_call_ct" != "1" ]]; then
        die "Please define a record type, use -t stop or -t attempt" 64
    fi
fi

## SALT specific options
# Validate unsupported combinations for time-disposition reporting (-j).
if [[ "$timedisposition" == "4" ]]; then
    if [[ "$total_call_ct" == "1" ]]; then
        die "Invalid option, \"-j\" and \"-l\" cannot be used together" 64
    fi

    if [[ "$recordtype" == "START" ]]; then
        die "Please use -t stop or -t attempt" 64
    fi
fi

if [[ "$DEBUG" == "1" ]]; then
    printf 'DEBUG: ACT file: %s\n' "${act_files[@]}"
fi

# ----------------------------
# Execute grepACT commands and print output to screen
# ----------------------------

## Print SBC Hostname header
echo "---$sbc_hostname---"

# print count of ACT files being searched. Check for recordtype being set
if [[ "$recordtype" == "START" ]]; then
    echo "Searching $files_searched ACT file(s) for START CDRs"
elif [[ "$recordtype" == "STOP" ]]; then
    echo "Searching $files_searched ACT file(s) for STOP CDRs"
elif [[ "$recordtype" == "ATTEMPT" ]]; then
    echo "Searching $files_searched ACT file(s) for ATTEMPT CDRs"
else
    echo "Searching $files_searched ACT file(s) for START, STOP, ATTEMPT CDRs"
fi

cd "$evlog_dir"
echo

if [[ "$quicklines" -gt 0 ]]; then
    read_act_files "${act_files[@]}" |
        filter_record_type |
        filter_search |
        filter_additional_search |
        filter_exclude_search |
        filter_emergency |
        filter_disconnect_reason |
        filter_duplicates |
        filter_print_fields |
        filter_total_call_counts |
        filter_time_disposition |
        "$quickcmd" -n "$quicklines" || true
else
    read_act_files "${act_files[@]}" |
        filter_record_type |
        filter_search |
        filter_additional_search |
        filter_exclude_search |
        filter_emergency |
        filter_disconnect_reason |
        filter_duplicates |
        filter_print_fields |
        filter_total_call_counts |
        filter_time_disposition || true
fi

exit 0