#!/bin/bash
# GVSOC Full Regression Wrapper (drop-in for Imperas)
# Usage: ./run_gvsoc_full_regress.sh [yaml_name] [trace_log]
#   yaml_name: ci_check (default) | full_covg_no_pulp | rel_check | any yaml in cv32e40p/regress/
#   trace_log: NO (default, fast) | YES (slow, produces trace_core.log)
#
# This wrapper uses cv_regress with --iss GVSOC to generate a bash regression
# script equivalent to the Imperas flow. Coverage is always enabled (--cov).
#
# Prerequisites (override per host via environment variables):
#   - micromamba env   (MAMBA_ENV, default gvsoc_env_3_12)
#   - Questa module    (QUESTA_MODULE, default questa/2025.3)
#   - libgvsoc_rvvi_v2.so built in vendor_lib/gvsoc_rvvi/

set -u
set -o pipefail

YAML=${1:-cv32e40p_ci_check}
TRACE=${2:-NO}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJ_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
REGRESS_DIR=$PROJ_ROOT/cv32e40p/regress
SIM_DIR=$PROJ_ROOT/cv32e40p/sim/uvmt
RESULTS=$SIM_DIR/regress_results
STAMP=$(date +%Y%m%d_%H%M%S)
LOG=$RESULTS/gvsoc_${YAML}_${STAMP}.log
SH=$RESULTS/regress_${YAML}_${STAMP}.sh

mkdir -p "$RESULTS"

echo "===== GVSOC full regression =====" | tee "$LOG"
echo "YAML:  $YAML" | tee -a "$LOG"
echo "TRACE: $TRACE" | tee -a "$LOG"
echo "LOG:   $LOG" | tee -a "$LOG"
echo "SH:    $SH" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# --- Env setup ---
source /etc/profile.d/modules.sh
module load "${QUESTA_MODULE:-questa/2025.3}"
eval "$(micromamba shell hook --shell bash)"
micromamba activate "${MAMBA_ENV:-gvsoc_env_3_12}"

which vsim vlog python3 | tee -a "$LOG"
echo "" | tee -a "$LOG"

# --- Generate regression script via cv_regress ---
cd "$PROJ_ROOT"
python3 bin/cv_regress \
    -f "${YAML}.yaml" \
    -p cv32e40p \
    -s vsim \
    --iss GVSOC \
    --cov \
    --makearg "ENABLE_TRACE_LOG=${TRACE}" \
    --sh \
    -o "$SH" 2>&1 | tee -a "$LOG"

if [ ! -f "$SH" ]; then
    echo "ERROR: cv_regress did not produce $SH" | tee -a "$LOG"
    exit 1
fi

echo "Generated: $(wc -l < $SH) lines" | tee -a "$LOG"
echo "Builds: $(grep -c 'Running build' $SH)" | tee -a "$LOG"
echo "Tests:  $(grep -c 'Running test' $SH)" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# --- Execute ---
echo "===== START at $(date) =====" | tee -a "$LOG"
cd "$SIM_DIR"
bash "$SH" 2>&1 | tee -a "$LOG"
rc=${PIPESTATUS[0]}
echo "===== END at $(date) rc=$rc =====" | tee -a "$LOG"

# --- Recheck with robust log parser ---
echo "" | tee -a "$LOG"
echo "===== RECHECK RESULTS =====" | tee -a "$LOG"
python3 "$PROJ_ROOT/cv32e40p/sim/uvmt/recheck_gvsoc_logs.py" "$SH" 2>&1 | tee -a "$LOG" || true

# --- Coverage merge ---
if grep -q "COV=YES" "$SH"; then
    echo "" | tee -a "$LOG"
    echo "===== COVERAGE MERGE =====" | tee -a "$LOG"
    cd "$SIM_DIR"
    make cov_merge MERGE=YES CV_CORE=cv32e40p SIMULATOR=vsim 2>&1 | tee -a "$LOG" || true
fi

echo "" | tee -a "$LOG"
echo "===== DONE =====" | tee -a "$LOG"
exit $rc
