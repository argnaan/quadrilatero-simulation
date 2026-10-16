###############################################################################
#
# Copyright 2020 OpenHW Group
# 
# Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     https://solderpad.org/licenses/
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
#
###############################################################################
#
# Makefile for the CV32E40P "uvmt_cv32" testbench.  Substantially modified
# from the original Makefile for the RI5CY testbench.
#
###############################################################################
# 
# Copyright 2019 Claire Wolf
# Copyright 2019 Robert Balas
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.
#
# Original Author: Robert Balas (balasr@iis.ee.ethz.ch)
#
###############################################################################

# "Constants"
MAKE                  = make
MAKE_PATH            := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
export CORE_V_VERIF   = $(abspath $(MAKE_PATH)/../../..)
export CV_CORE       ?= cv32e40px

DPI_DASM_SPIKE_REPO  ?= https://github.com/riscv/riscv-isa-sim.git

include ../ExternalRepos.mk
include $(CORE_V_VERIF)/mk/uvmt/uvmt.mk


# --- GVSOC: common variables (GVSOC_TRACE and GVSOC DPI modes) ---
# GVSOC_RVVI_HOME, GVSOC_COREV_PULP, GVSOC_FPU, GVSOC_ZFINX, GVSOC_CONFIG
# are defined in mk/Common.mk.
GVSOC_ELF := $(SIM_TEST_PROGRAM_RESULTS)/$(TEST_PROGRAM)$(OPT_RUN_INDEX_SUFFIX).elf

# --- ISS=GVSOC_TRACE: offline trace comparison ---
# RTL sim -> GVSOC standalone sim -> compare_traces.py
ifeq ($(ISS),GVSOC_TRACE)

SIM_TRACE     ?= $(SIM_RUN_RESULTS)/trace_core.log
GVSOC_TRACE   ?= $(GVSOC_RVVI_HOME)/trace_$(TEST)_$(CFG).log
COMPARE_TRACE ?= $(CORE_V_VERIF)/bin/compare_traces.py

test: generate_gvsoc_config run_gvsoc compare_traces

generate_gvsoc_config:
	@echo "--- Generating GVSOC config for trace mode ---"
	$(MAKE) -C $(GVSOC_RVVI_HOME) config \
		BINARY=$(GVSOC_ELF) \
		COREV_PULP=$(GVSOC_COREV_PULP) \
		FPU=$(GVSOC_FPU) \
		ZFINX=$(GVSOC_ZFINX) \
		COREV_CLUSTER=$(GVSOC_COREV_CLUSTER) \
		NUM_MHPMCOUNTERS=$(GVSOC_NUM_MHPMCOUNTERS)

run_gvsoc:
	@echo "--- Running GVSOC standalone ---"
	$(MAKE) -C $(GVSOC_RVVI_HOME) trace \
		BINARY=$(GVSOC_ELF) \
		COREV_PULP=$(GVSOC_COREV_PULP) \
		FPU=$(GVSOC_FPU) \
		ZFINX=$(GVSOC_ZFINX) \
		COREV_CLUSTER=$(GVSOC_COREV_CLUSTER) \
		TRACE=$(GVSOC_TRACE)

compare_traces:
	@echo "--- Comparing RTL vs GVSOC traces ---"
	$(COMPARE_TRACE) $(SIM_TRACE) $(GVSOC_TRACE)
endif

# --- ISS=GVSOC: DPI co-simulation (step-n-compare in-process) ---
# Generates per-CFG config, then runs Questa with libgvsoc_rvvi.so.
ifeq ($(ISS),GVSOC)

# vpi_control(vpiFinish) causes vsim to return non-zero exit code (215).
# Ignore vsim exit code and use log-based pass/fail detection instead.
VSIM_RUN_PREFIX  = -
CHECK_SIM_RESULT = YES

# Log-based pass/fail detection for ISS=GVSOC DPI
# Detection logic (in order of precedence):
# 1. If UVM_ERROR/FATAL are present and non-zero -> FAIL
# 2. If "Errors: 0" is present -> PASS (vpiFinish may terminate early)
# 3. If UVM_ERROR/FATAL are present and zero -> PASS
# 4. If none of the above -> FAIL (unable to determine status)
POST_TEST = if grep -q "Errors: 0" $(RUN_DIR)/vsim-$(VSIM_TEST).log && grep -q "SIMULATION PASSED" $(RUN_DIR)/vsim-$(VSIM_TEST).log; then echo "GVSOC DPI: PASSED"; exit 0; else echo "GVSOC DPI: FAILED"; exit 1; fi

test: generate_gvsoc_dpi_config hex run

# GNU make merges `test` prerequisites across rules. vsim.mk's `test: hex run`
# is parsed before this file, so generate_gvsoc_dpi_config is appended LAST and
# the config regenerates AFTER the sim has already consumed the stale on-disk
# copy. This edge makes regen a prerequisite of `run`, guaranteeing a fresh
# config before each DPI simulation (make test self-heals a stale config).
run: generate_gvsoc_dpi_config

# COREV_CLUSTER is intentionally NOT passed here (unlike the GVSOC_TRACE recipes
# generate_gvsoc_config / run_gvsoc above): the cluster model is a known DPI
# divergence (WONTFIX), so the DPI config is generated single-core.
# The core configuration is baked into the iss_v2 target name.
GVSOC_V2_TARGET = cv32e40p-v2-standalone$(if $(filter True,$(GVSOC_ZFINX)),-zfinx,$(if $(filter True,$(GVSOC_FPU)),-fpu,$(if $(filter True,$(GVSOC_COREV_PULP)),,-nopulp)))
generate_gvsoc_dpi_config:
	@echo "--- Generating GVSOC config for DPI (CFG=$(CFG), iss_v2) ---"
	$(MAKE) -C $(GVSOC_RVVI_HOME) config-v2 \
		BINARY=$(GVSOC_ELF) \
		V2_TARGET=$(GVSOC_V2_TARGET)
ifeq ($(GVSOC_ZFINX),True)
	@echo "--- Building ZFINX iss_v2 GVSOC bridge ---"
	$(MAKE) -C $(GVSOC_RVVI_HOME) libgvsoc_rvvi_v2_zfinx.so
endif

endif