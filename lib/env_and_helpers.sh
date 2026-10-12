#!/bin/bash
# ---------------------------------------------------------------------------
# Helpers and Environment setup
# ---------------------------------------------------------------------------

# Chargement de la configuration globale si elle existe
if [ -f "${SCRIPT_DIR}/config/global.env" ]; then
    source "${SCRIPT_DIR}/config/global.env"
fi



log()   { echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] ${*:2}"; }
die()   { log ERROR "$2"; exit "$1"; }

# Using the caller's main script for usage
usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "${SCRIPT_DIR}/load_csv_generic.sh" | sed 's/^# \{0,1\}//' | sed '$d'; }

to_native_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$1"
    elif command -v wslpath >/dev/null 2>&1; then
        wslpath -m "$1"
    else
        echo "$1"
    fi
}
