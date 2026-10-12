#!/bin/bash
# ---------------------------------------------------------------------------
# Pre-checks
# ---------------------------------------------------------------------------
[ -z "${FILE_SPEC}" ]            && { usage; die 1 "-f <file|pattern> is mandatory"; }
[ -z "${TARGET_TABLE}" ]         && { usage; die 1 "-t <table> is mandatory"; }
[ -z "${TDPID}" ]                && die 1 "TDPID is not set"
[ -z "${TDENV+x}" ]              && log WARN "TDENV is not set - using no environment prefix"
[ -f "${TPT_SCRIPT}" ]           || die 1 "TPT script not found: ${TPT_SCRIPT}"

# Detect tbuild and bteq (Linux native, Git Bash, or WSL calling Windows .exe)
TBUILD_CMD="tbuild"
BTEQ_CMD="bteq"
if ! command -v "${TBUILD_CMD}" >/dev/null 2>&1 && command -v tbuild.exe >/dev/null 2>&1; then
    TBUILD_CMD="tbuild.exe"
fi
if ! command -v "${BTEQ_CMD}" >/dev/null 2>&1 && command -v bteq.exe >/dev/null 2>&1; then
    BTEQ_CMD="bteq.exe"
fi

command -v "${TBUILD_CMD}" >/dev/null || die 1 "tbuild / tbuild.exe not found in PATH (TTU not installed?)"
command -v "${BTEQ_CMD}"   >/dev/null || die 1 "bteq / bteq.exe not found in PATH"

case "${LOAD_MODE}" in
    replace|append) ;;
    *) die 1 "-m must be 'replace' or 'append' (got '${LOAD_MODE}')" ;;
esac

# Expand the file spec (exact file or wildcard pattern)
shopt -s nullglob
FILES=( ${FILE_SPEC} )
shopt -u nullglob
[ ${#FILES[@]} -eq 0 ] && die 1 "No file matches: ${FILE_SPEC}"

DIRECTORY_PATH="$(cd "$(dirname "${FILES[0]}")" && pwd)"
FILE_NAME="$(basename "${FILE_SPEC}")"
for f in "${FILES[@]}"; do
    [ "$(cd "$(dirname "${f}")" && pwd)" = "${DIRECTORY_PATH}" ] \
        || die 1 "All files must be in the same directory (pattern: ${FILE_SPEC})"
    [ -s "${f}" ] || die 1 "File is empty or unreadable: ${f}"
done

FQ_TABLE="${TARGET_DB}.${TARGET_TABLE}"

# Password: Teradata Wallet by default; TD_PASSWORD overrides it (dev/sandpit only)
if [ -n "${TD_PASSWORD}" ]; then
    BTEQ_PWD="${TD_PASSWORD}"
    TPT_PWD="${TD_PASSWORD//\'/\'\'}"              # TPT: escape single quotes
    log WARN "TD_PASSWORD is set - using a plain password instead of Teradata Wallet"
else
    BTEQ_PWD="\$tdwallet(${TD_USER})"
    TPT_PWD="\"\$tdwallet(${TD_USER})\""
fi

# MultipleReaders (several instances on ONE file) is incompatible with a
# wildcard scan, where parallelism comes from distributing files to instances.
MULTIPLE_READERS="N"
case "${FILE_SPEC}" in
    *\**|*\?*) [ ${READER_INSTANCES} -gt ${#FILES[@]} ] && READER_INSTANCES=${#FILES[@]} ;;
    *)         [ ${READER_INSTANCES} -gt 1 ] && MULTIPLE_READERS="Y" ;;
esac

# Extract metadata from filename using the patterns
FIRST_BASENAME="$(basename "${FILES[0]}")"
AUTO_BATCH_ID=""
[ -n "${BATCH_ID_PATTERN}" ] && AUTO_BATCH_ID=$(echo "${FIRST_BASENAME}" | sed -n "${BATCH_ID_PATTERN}")
BATCH_ID="${CLI_BATCH_ID:-${AUTO_BATCH_ID}}"

AUTO_TS=""
[ -n "${TIMESTAMP_PATTERN}" ] && AUTO_TS=$(echo "${FIRST_BASENAME}" | sed -n "${TIMESTAMP_PATTERN}")
META_TS="${CLI_TIMESTAMP:-${AUTO_TS}}"

# If no batch ID or timestamp was provided/extracted, fallback to the current time.
# Use unix epoch for the batch ID (fits in a standard INTEGER) and ISO for the timestamp.
if [ -z "${BATCH_ID}" ] || [ -z "${META_TS}" ]; then
    CURRENT_EPOCH="$(date '+%s')"
    CURRENT_ISO="$(date '+%Y-%m-%d %H:%M:%S')"
    [ -z "${BATCH_ID}" ] && BATCH_ID="${CURRENT_EPOCH}"
    [ -z "${META_TS}" ]  && META_TS="${CURRENT_ISO}"
fi

# Column count in the file header
HEADER_COLS=$(head -1 "${FILES[0]}" | tr -d '\r' | awk -F"${DELIMITER}" '{print NF}')

log INFO "System      : ${TDPID}  user=${TD_USER}  (env prefix '${TDENV}')"
log INFO "Utility DB  : ${WRK_DB}"
log INFO "Target      : ${FQ_TABLE}  mode=${LOAD_MODE}"
log INFO "Files       : ${#FILES[@]} file(s) in ${DIRECTORY_PATH}  pattern='${FILE_NAME}'"
log INFO "Header      : ${HEADER_COLS} column(s), delimiter '${DELIMITER}'"
[ -n "${BATCH_ID}" ] && log INFO "Batch ID    : ${BATCH_ID}"
[ -n "${META_TS}" ]  && log INFO "Timestamp   : ${META_TS}"
