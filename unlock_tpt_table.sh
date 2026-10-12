#!/bin/bash
#/***************************************************
# FDJ
#
# Finance domain - Oracle Fusion - Unlock TPT Table
#
# Unlocks a Teradata staging table that was left locked (FastLoad Paused 
# or MultiLoad Paused) after a failed TPT load.
# 
# Usage:
#   unlock_tpt_table.sh -t <table> [-d <database>] [-u <user>] [-m replace|append] [-v <jobvariables_file>]
#
#   -t  Target table name (mandatory unless specified in -v)
#   -d  Target database (default: ${TDENV}${DB_STG})
#   -u  Logon user (default: ${TDENV}${SID_ADM_USER})
#   -m  replace : Tries to restart the last failed TPT job to resolve the lock
#       append  : Releases MultiLoad lock (RELEASE MLOAD) via BTEQ
#   -v  Job variables configuration file. Values in this file serve as defaults.
#
#****************************************************/

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/env_and_helpers.sh"
source "${LIB_DIR}/parse_args.sh" "$@"

[ -z "${TARGET_TABLE}" ] && die 1 "Target table (-t or TargetTable in -v) is required."
[ -z "${TDPID}" ] && die 1 "TDPID environment variable is required."

FQ_TABLE="${TARGET_DB}.${TARGET_TABLE}"

if [ "${LOAD_MODE}" = "append" ]; then
    log INFO "Mode is 'append' (MultiLoad). Sending RELEASE MLOAD to ${FQ_TABLE}..."
    
    BTEQ_CMD="bteq"
    if ! command -v "${BTEQ_CMD}" >/dev/null 2>&1 && command -v bteq.exe >/dev/null 2>&1; then
        BTEQ_CMD="bteq.exe"
    fi
    command -v "${BTEQ_CMD}" >/dev/null || die 1 "bteq / bteq.exe not found in PATH."

    if [ -n "${TD_PASSWORD}" ]; then
        BTEQ_PWD="${TD_PASSWORD}"
    else
        BTEQ_PWD="\$tdwallet(${TD_USER})"
    fi

    BTEQ_OUT=$(${BTEQ_CMD} <<EOF 2>&1
.logon ${TDPID}/${TD_USER},${BTEQ_PWD}
RELEASE MLOAD ${FQ_TABLE};
.logoff
.quit
EOF
)
    BTEQ_RC=$?
    if [ ${BTEQ_RC} -ne 0 ]; then
        echo "${BTEQ_OUT}"
        die 2 "Failed to unlock table (bteq rc=${BTEQ_RC})."
    fi
    log INFO "Table ${FQ_TABLE} unlocked successfully."

else
    log INFO "Mode is 'replace' (FastLoad). To unlock a table locked by TPT LOAD, we must resume the interrupted job."
    
    # Chercher le dernier répertoire de job généré pour cette table
    LAST_JOB_DIR=$(ls -1td "${WORK_DIR}/LOAD_${TARGET_TABLE}_"* 2>/dev/null | head -1)
    
    if [ -z "${LAST_JOB_DIR}" ]; then
        die 1 "Impossible de trouver l'historique du job dans ${WORK_DIR} pour la table ${TARGET_TABLE}. Pour libérer la table manuellement sans redémarrer le job, vous devrez faire un DROP/CREATE de la table."
    fi
    
    JOB_NAME=$(basename "${LAST_JOB_DIR}")
    log INFO "Dernier job identifié : ${JOB_NAME}. Tentative de reprise (restart)..."
    
    TBUILD_CMD="tbuild"
    if ! command -v "${TBUILD_CMD}" >/dev/null 2>&1 && command -v tbuild.exe >/dev/null 2>&1; then
        TBUILD_CMD="tbuild.exe"
    fi
    command -v "${TBUILD_CMD}" >/dev/null || die 1 "tbuild / tbuild.exe not found in PATH."

    JOBVARS="${LAST_JOB_DIR}/jobvars.txt"
    TPT_SCRIPT="${LIB_DIR}/load_csv_generic.tpt"
    
    log INFO "Exécution de la reprise de TPT : ${TBUILD_CMD} -f ${TPT_SCRIPT} -v ${JOBVARS} -j ${JOB_NAME}"
    ${TBUILD_CMD} -f "$(to_native_path "${TPT_SCRIPT}")" -v "$(to_native_path "${JOBVARS}")" -j "${JOB_NAME}"
    RC=$?
    
    if [ $RC -eq 0 ] || [ $RC -eq 4 ]; then
        log INFO "Le job a repris et s'est terminé correctement. La table ${FQ_TABLE} est maintenant déverrouillée."
        
        # Tentative optionnelle de mise à jour des métadonnées (puisque l'orchestrateur Shell a été bypassé par le -r)
        if [ -f "${LAST_JOB_DIR}/jobvars.txt" ]; then
            log INFO "Pour information, ce script utilitaire ne relance pas l'étape de mise à jour des métadonnées BICC (update_metadata.sh)."
        fi
    else
        die 2 "Le redémarrage du job a échoué (rc=${RC}). Veuillez corriger la cause de l'erreur dans le fichier source ou purger manuellement la table."
    fi
fi

exit 0
