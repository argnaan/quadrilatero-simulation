#!/bin/bash
# GVSOC_TRACE regression (debug/triage tool, not the maintained co-sim path):
# per test, RTL-only sim -> standalone gvrun -> bin/compare_traces.py.
source /etc/profile.d/modules.sh 2>/dev/null
module load "${QUESTA_MODULE:-questa/2025.3}" 2>/dev/null
eval "$(micromamba shell hook --shell=bash)" 2>/dev/null
micromamba activate "${MAMBA_ENV:-gvsoc_env_3_12}" 2>/dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Test list: single source of truth in cv32e40p/regress.
# Each entry is "<test> <cfg>". Order matters: the first entry of each cfg compiles
# the testbench (COMP=YES); the rest of that cfg run COMP=NO in parallel.
# Override the list with TRACE_TESTLIST=<file>.
TRACE_TESTLIST="${TRACE_TESTLIST:-$SCRIPT_DIR/../../regress/cv32e40p_gvsoc_trace.yaml}"
if [ ! -f "$TRACE_TESTLIST" ]; then
  echo "ERROR: GVSOC_TRACE test list not found: $TRACE_TESTLIST" >&2
  exit 1
fi
mapfile -t TESTS < <(grep -E '^[[:space:]]*-[[:space:]]+' "$TRACE_TESTLIST" \
                       | sed -E 's/^[[:space:]]*-[[:space:]]+//; s/[[:space:]]+#.*$//')
if [ "${#TESTS[@]}" -eq 0 ]; then
  echo "ERROR: no tests parsed from $TRACE_TESTLIST" >&2
  exit 1
fi

MAX_PARALLEL=4
RESULTS_FILE=$(mktemp /tmp/gvsoc_trace_results.XXXXXX)
LOGDIR=${GVSOC_TRACE_LOGDIR:-/tmp}

# PASS = compare_traces.py "SUCCESS: N instructions verified" with N>=1.
# N==0 means an empty RTL trace (nothing compared) -> FAIL, not a pass.
detect_pass() { grep -qE "SUCCESS:[[:space:]]*[1-9][0-9]* instructions verified" "$1" 2>/dev/null; }

run_test() {
  local test=$1 cfg=$2 comp=$3
  local log="${LOGDIR}/gvsoc_trace_${test}_${cfg}.log"
  make test TEST="${test}" CFG="${cfg}" ISS=GVSOC_TRACE COMP="${comp}" > "${log}" 2>&1
  if detect_pass "${log}"; then
    echo "PASS ${test}/${cfg}" >> "${RESULTS_FILE}"
  else
    echo "FAIL ${test}/${cfg}" >> "${RESULTS_FILE}"
  fi
}

echo "Starting GVSOC_TRACE regression: ${#TESTS[@]} tests, max ${MAX_PARALLEL} parallel"
echo "Results file: ${RESULTS_FILE}"
echo "============================================================"

declare -A CFG_COMPILED
pids=()
for entry in "${TESTS[@]}"; do
  test=$(echo "$entry" | awk '{print $1}')
  cfg=$(echo "$entry" | awk '{print $2}')

  if [ -z "${CFG_COMPILED[$cfg]}" ]; then
    # First test of this cfg compiles the TB serially (COMP=YES); the rest run
    # COMP=NO in parallel, so no build race.
    echo "[comp] CFG=${cfg} via TEST=${test} (COMP=YES, serial) ..."
    run_test "$test" "$cfg" "YES"
    CFG_COMPILED[$cfg]=1
  else
    run_test "$test" "$cfg" "NO" &
    pids+=($!)
    if [ ${#pids[@]} -ge $MAX_PARALLEL ]; then
      wait "${pids[0]}"
      pids=("${pids[@]:1}")
    fi
  fi
done

for pid in "${pids[@]}"; do wait "$pid"; done

echo "============================================================"
P=$(grep -c '^PASS ' "${RESULTS_FILE}" 2>/dev/null)
F=$(grep -c '^FAIL ' "${RESULTS_FILE}" 2>/dev/null)
echo "GVSOC_TRACE regression complete: ${P}/${#TESTS[@]} PASS, ${F} FAIL"
if [ "${F}" -gt 0 ]; then
  echo "--- FAILURES ---"
  grep '^FAIL ' "${RESULTS_FILE}"
fi
echo "Per-test logs: ${LOGDIR}/gvsoc_trace_<test>_<cfg>.log"
