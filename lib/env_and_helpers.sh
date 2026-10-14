#!/bin/bash
# ---------------------------------------------------------------------------
# Helpers and Environment setup (POSIX / Unix)
# ---------------------------------------------------------------------------

# Load global configuration if present
if [ -f "${SCRIPT_DIR}/config/global.env" ]; then
    source "${SCRIPT_DIR}/config/global.env"
fi

log()   { echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] ${*:2}"; }
die()   { log ERROR "$2"; exit "$1"; }

# Using the caller's main script for usage
usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "${SCRIPT_DIR}/load_csv_generic.sh" | sed 's/^# \{0,1\}//' | sed '$d'; }

to_native_path() {
    echo "$1"
}
