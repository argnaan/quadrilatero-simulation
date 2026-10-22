# GVSOC vs Imperas OVPSIM — CV32E40P ISS Reference-Model Evaluation

CV32E40P functional verification — comparison of the GVSOC open-source ISS
against the Imperas OVPSIM reference model in RVVI DPI step-and-compare.

> **Data provenance.** Every number below is dated and sourced. The GVSOC
> regression figures come from the last full FAST2 `no_pulp` run on 2026-05-20
> (wall-clock 11h53m, completed 2026-05-22), analysed on 2026-05-26. The frozen
> ISS revision under review (gvsoc-core `22216971`, gvsoc-pulp `9d9835a`) was
> point-validated on 2026-06-12 (targeted 14-test suite + a 4-configuration
> smoke, all PASS); it is behaviourally equivalent to the 2026-05-20 code (the
> intervening work was history cleanup plus two CV32E40P-only changes, verified
> by a preprocessor strip-check against upstream and by smoke regression). A
> fresh full regression on the exact frozen revision has not yet been run — see
> the roadmap, Sprint 0 gate.
>
> **What "Imperas baseline" means here (read this first).** There is **no
> independently measured Imperas pass-count** in this repository. In RVVI
> step-and-compare, Imperas *is* the reference model — it defines the expected
> architectural state, so on the curated run subset it passes **by
> construction**, not by an audited tally. The official OpenHW regression that
> would produce real Imperas pass counts runs on an **external Metrics cloud**
> (where the Imperas licence lives), not in this repo. Imperas was also not
> trivially 100% on everything: several tests are run with comparison disabled
> (`iss: 0`) or excluded *because* they miscompare against the reference model
> (see §2.2). So this document compares GVSOC against Imperas-as-reference, and
> is explicit about where the comparison is and is not apples-to-apples (§3).

---

## 1. Executive Summary

GVSOC is a viable open-source alternative to Imperas OVPSIM as the ISS
reference model for CV32E40P co-simulation. On the FAST2 `no_pulp` **bring-up**
subset it reaches near-parity with the OVPSIM reference, with a remaining gap
that is now fully characterised and **larger than a single failing test** once
the suite asymmetry is accounted for honestly. The full OVPSIM workload (the
PULP-based sign-off regression) is a larger, separately-scoped target — see
§3.6-3.7.

| Metric | Value | Source |
|--------|-------|--------|
| GVSOC FAST2 `no_pulp` DPI co-sim PASS | **644 / 651 (98.92%)** | regression 2026-05-20 |
| GVSOC ISS-attributable pass rate (excl. 5 testbench deadlocks) | **~99.69%** (649/651) | derived |
| Imperas OVPSIM on the same flow | reference model — **golden by definition**, no measured count in-repo | §2.2 |
| FAST2 active tests vs full `no_pulp` active tests | **25 vs 43** (18 GVSOC-excluded) | regress yamls |
| Genuine ISS functional divergence (GVSOC) | **1** (`generic_exception_test`, `mepc`) | under investigation |
| Cross-target build safety | **GREEN** — 287 `.so`, all non-CV32E40P targets build | 2026-05-25 |

The headline 644/651 is measured on **FAST2** (25 tests, 651 test×seed
executions). The true gap to Imperas has three parts:

1. **1 genuine ISS divergence** — `generic_exception_test` `mepc` mismatch.
2. **5 DPI-bridge deadlocks** — a testbench-infrastructure gap (the GVSOC bridge
   has no reconverge-on-mismatch; Imperas does — see §3.2), not an ISS error.
3. **18 debug/interrupt/ebreak/illegal-instr tests excluded from FAST2** — these
   are kept *active* in the full `no_pulp` suite that Imperas runs, and were
   commented out **specifically for GVSOC** (DPI co-sim trap/timing
   divergences). `no_pulp` full-suite parity requires clearing these (§3.4); the
   broader OVPSIM replacement (the PULP regression) is §3.6-3.7.

GVSOC is positioned as a "good-enough" open-source ISS for fast CI iteration on
the directed/random arithmetic, CSR and ISA suites — not yet a drop-in
replacement for OVPSIM across the full debug/interrupt suite at coverage
sign-off.

Note on scope: `no_pulp` is a **bring-up scaffold**, not an OpenHW sign-off
configuration. The real OVPSIM workload GVSOC must replace is the PULP-based
simulation regression (XPULP + FPU + interrupt/debug on the seven CFG_P configs,
~32 666 randomized runs). §3.6 details that target; §3.7 classifies what GVSOC
must run versus what stays with the RTL/formal sign-off.

---

## 2. The two reference models

### 2.1 Architectural comparison

| Dimension | Imperas OVPSIM / ImperasDV | GVSOC |
|-----------|----------------------------|-------|
| Licence | Commercial, proprietary | Open source (Apache 2.0) |
| Source | Closed binary (`.so`) | C++, modifiable |
| Role in flow | RVVI reference model (default `ISS ?= IMPERAS`) | RVVI reference model (`ISS=GVSOC`) |
| Configuration | `ovpsim.ic` / ImperasDV model | JSON config from a Python target |
| SV interface | RVVI (`uvma_rvvi_ovpsim`) | RVVI (`rvvi_trace2api`) |
| Mismatch policy | `ON_MISMATCH_RECONVERGE` (re-sync ref to RTL) | none — flag, then bridge waits |
| Bug fixing | Not possible without vendor support | Direct in the C++ source |
| Where it runs in official CI | External Metrics cloud | Local (built from source) |

Imperas is the **default** reference model: `ISS ?= IMPERAS` and `USE_ISS`
auto-enables when `IMPERAS_HOME` is set (`mk/uvmt/uvmt.mk:73-84`). GVSOC is
selected with `ISS=GVSOC`, which swaps the compiled reference `.so` and the wrap
module (`mk/uvmt/vsim.mk:147-161`).

### 2.2 "Imperas = 100%" is golden-by-definition, not a measurement

In RVVI step-and-compare the testbench steps the RTL one retire at a time and
compares architectural state (PC, GPR writes, CSR writes) against the reference
model. A test PASSES when every retired-instruction comparison matches the
reference **and** the test's own self-check succeeds. Because Imperas *is* the
reference, it cannot "fail the comparison" by construction — but a test can
still FAIL under Imperas from an RTL bug, a test bug, or infrastructure.

Crucially, even under Imperas the suite is **curated** so that the run subset
passes:

- `debug_test_known_miscompares` runs with `iss: 0` — step-and-compare disabled,
  test.yaml: *"tests with known failures in step-and-compare"*.
- embench: *"ISS must be disabled as the accesses to the cycle counter … causes
  step and compare mismatches"* (`tests/embench/README.md:80-81`).
- `all_csr_por.c` / `modeled_csr_por.c` headers note *"Step-and-compare against
  RM mismatch"*.

So **real divergences existed even with Imperas** and were handled by disabling
comparison or excluding the test. The "651/651 (100%, golden)" figure that
appeared in earlier versions of this report was the reference column inside a
GVSOC evaluation — golden by role, not an audited Imperas pass/fail tally. Any
hard measured Imperas pass-rate would have to come from the external
Metrics-cloud regression, which is not stored in this repo.

The authoritative Imperas-based sign-off lives in the official OpenHW CV32E40P
verification reports. The published **v1.8.3 milestone** report (generated
2024-05-14 with Questa 2023.2_1, merged across all 7 configurations) records:

| Official OpenHW v1.8.3 sign-off | Result | Source (openhwgroup/programs @ `cv32e40p_v1.8.3`) |
|---------------------------------|--------|---------------------------------------------------|
| Functional coverage (overall) | **98.44%** | `…/Reports/Coverage/Function_coverage/CFG_P_F0/htmlcovreport` |
| — covergroups | 95.33% (456 groups) | same |
| — assertions | 100% (176/176) | same |
| — cover directives | 100% (194/194) | same |
| Code coverage (overall) | **99.56%** | `…/Reports/Coverage/Code_coverage/CFG_P` |
| — statements / branches | 99.80% / 99.64% | same |
| Regression (e.g. CFG_P INT-DEBUG group) | 1593/1595 PASS | `…/Reports/Simulation/CFG_P/NR_QUESTA_INT_DEBUG` |

That regression is a **massive randomized run** (thousands of test×seed
executions across 7 configs × 4-5 groups, on the Metrics cloud with Imperas as
the reference). These are the source of record for the Imperas result. **They
are not comparable to the GVSOC 644/651 below**: a coverage percentage and a
cloud-scale randomized pass-tally are different metrics from a 25-test FAST2
step-and-compare pass-rate. This document reports our GVSOC measurements and
cites — but does not re-measure — the official Imperas sign-off.

---

## 3. Regression comparison (FAST2 `no_pulp`, 2026-05-20)

### 3.1 Apples-to-apples — and where it is not

The comparison is structurally fair on the main axis: **same RTL DUT, same UVM
test, same `make test` invocation, same RVFI→RVVI wiring file**
(`uvmt_cv32e40p_iss_wrap_common.svh`), with only the make variable `ISS=GVSOC`
vs `ISS=IMPERAS` swapping the reference `.so` and the wrap module
(`uvmt_cv32e40p_tb.sv:585-596`).

It is **not** perfectly symmetric at the harness/policy level, and these
asymmetries explain the GVSOC-only failure modes:

| Asymmetry | Imperas | GVSOC | Consequence |
|-----------|---------|-------|-------------|
| Mismatch recovery | `ON_MISMATCH_RECONVERGE` re-syncs the ref to RTL and continues | none — the batch bridge flags and waits | a *sustained* mismatch deadlocks the GVSOC bridge (the 5 deadlock FAILs) |
| Trap-CSR wiring | standard RVVI CSR formula | extra `RVVI_SET_TRAP_CSR` macro (wdata-direct for `mepc`/`mcause`/`mtval`/`mstatus`) | CSR-compare wiring differs on the trap path |
| Volatile masking | compares HPM/cycle/debug CSRs | marks several volatile / compare-disabled | GVSOC does not model some counters cycle-accurately |
| Pass/fail detection | normal vsim result | log-grep (`Errors: 0` + `SIMULATION PASSED`) | GVSOC ignores vsim exit code (vpiFinish non-zero) |

The single most important asymmetry is the **missing reconverge**: it is the
structural reason GVSOC hangs on a sustained CSR mismatch where Imperas would
re-sync and carry on.

### 3.2 Two suites — FAST2 (GVSOC) vs full `no_pulp` (Imperas)

| Suite | Active tests | Run with | Note |
|-------|-------------|----------|------|
| `cv32e40p_full_covg_no_pulp.yaml` | **43** | Imperas (default) | 1 Imperas-era exclusion (`mhpmcounter29_csr_access_test_2`, `iss:0`, Mike Thompson 2020) |
| `cv32e40p_full_covg_no_pulp_fast2.yaml` | **25** | GVSOC (`ISS=GVSOC`) | created for GVSOC; 18 debug/IRQ tests commented out |

FAST2 trims **18 tests** (not seeds) relative to the full suite: the
`corev_rand_debug*`, `corev_rand_interrupt*`, `debug_test*`, `interrupt_test`,
`interrupt_bootstrap`, `riscv_ebreak_test_0` and `corev_rand_illegal_instr_test`
families. Git blame shows all 18 exclusions were authored by one GVSOC commit
(`b044987e`, mpaci, 2026-04-12, *"feat(gvsoc): full regression infra"*), with
explicit per-test causes (ebreak→breakpoint timing, mscratch sp-swap handler
convention, random interrupt/debug trap nesting). The full suite
keeps all 18 active.

**Therefore the 644/651 below is GVSOC on the 25-test FAST2 subset, with the
hard debug/IRQ tests removed.** This is honest fast-CI parity, not full-suite
parity.

### 3.3 The FAST2 run — 644/651

Counting is at the test×seed level (random tests run up to 200 seeds), so 651
total executions across the 25 FAST2 tests.

| Outcome | Count | % |
|---------|-------|---|
| PASS | 644 | 98.92% |
| FAIL | 7 | 1.08% |
| — DPI-bridge deadlock (testbench, not ISS) | 5 | |
| — seed-specific random noise | 1 | |
| — genuine ISS divergence | 1 | |
| **ISS-attributable pass rate** | **649 / 651** | **99.69%** |

The 7 FAILs, classified:

| Test | Class | Root cause | Owner |
|------|-------|-----------|-------|
| `corev_rand_instr_test/153` | Random noise | seed-specific watchdog (>1.5 ms program), 0.17% baseline | INFO |
| `cv32e40p_readonly_csr_access_test/0` | DPI-bridge deadlock | sustained CSR mismatch → bridge stuck (no reconverge) | testbench |
| `generic_exception_test/0` | **Genuine ISS divergence** | `mepc` (CSR 0x341) mismatch, 10 consecutive PC mismatches @ retire #538 | **ISS — pending** |
| `hpmcounter_basic_test/0` | DPI-bridge deadlock | counter mismatch → bridge frozen ~retire #38k | testbench |
| `hpmcounter_hazard_test/0` | DPI-bridge deadlock | `mcountinhibit` (0x320) mismatch @ retire #5769 | testbench |
| `illegal_instr_test/0` | DPI-bridge deadlock | trap loop → bridge stuck | testbench |
| `perf_counters_instructions/0` | DPI-bridge deadlock | stalled ~37 min, auto-killed | testbench |

The 5 deadlocks share the §3.1 root cause (no consecutive-mismatch timeout /
reconverge). The single ISS-attributable failure is the `mepc` divergence.

### 3.4 The 18 FAST2-excluded tests — the rest of the gap to Imperas

These are **active in the full `no_pulp` suite Imperas runs** and excluded from
FAST2 for GVSOC. They are debug/interrupt/ebreak/illegal-instr tests whose
stated cause is a DPI co-sim trap/timing divergence (ebreak→breakpoint
pipeline-stage timing, `mscratch` sp-swap handler convention, random
interrupt/debug trap nesting). They are GVSOC-specific (Imperas does not exclude
them), but the limitation lives in the **GVSOC DPI co-sim trap/timing path**,
not necessarily the instruction model. Closing full-suite parity means bringing
these back onto the suite (roadmap Sprint 3 — likely a mix of fixes and formally
documented known divergences).

### 3.5 Broader multi-configuration snapshot (historical)

An earlier cross-configuration run (10 configs: default, pulp, pulp_fpu,
pulp_fpu_zfinx and cycle-latency variants) recorded **135/146 test×config PASS
(92.5%)**. Non-PASS there fall into documented known-limitation buckets: VP-timer (3),
software-test bugs (4), performance timeout (2), cluster-model simplification
(1). The PULP configurations additionally exercise ISS feature gaps not present
in `no_pulp` (hardware-loop outer-loop replay, round-to-nearest-max-magnitude FP
rounding, an FP-NaN/ZFINX interaction). These gaps are **not** a side-issue: they
are exactly the XPULP + FPU work that §3.6-3.7 identify as the real OVPSIM target,
sequenced in the roadmap (Sprint 4). They are out of scope only for the *initial*
`no_pulp` upstream PR, not for the migration.

> An offline RTL-vs-trace diagnostic path also exists (`ISS=GVSOC_TRACE`,
> standalone GVSOC → `compare_traces.py`). It is superseded by DPI
> step-and-compare and is **no longer used for parity assessment**; it is
> retained only as a quick deterministic debug aid.

---

### 3.6 The full OpenHW v1.8.3 regression — what we are really targeting

The v1.8.3 RTL freeze ("TRL-5") is signed off by **four independent methods**,
documented in the official milestone report (`openhwgroup/programs` @
`cv32e40p_v1.8.3`, `Project-Descriptions-and-Plans/CV32E40Pv2/Milestone-data/RTL_v1.8.3`
— see its `README.md` summary tables and `index.html` report hub):

1. **RISC-V ISA Formal Verification (primary).** Every RISC-V standard *and*
   XPULP custom instruction is formally proven against Sail golden models; Questa
   then generates per-instruction + OBI + pipeline assertions, formally checked on
   CFG_P and CFG_P_F0 (198 assertions, successful unbounded proofs).
2. **Simulation regression.** Used *only for what formal cannot model* — hardware
   loops, prefetch/fetch pipeline, interrupt/debug timing.
3. **RISCOF** architectural compliance (4 configs, all pass).
4. **Coverage** — functional 100% per covergroup (FPU / HWLOOP / Debug /
   Interrupts / OBI …), RTL code ~99.6-99.9%.

The seven configurations are **all XPULP-enabled** — there is no non-PULP config
in the sign-off:

| Config | ISA string | Variant axis |
|--------|------------|--------------|
| CFG_P | `RV32IMC_Zicsr_Zifencei_XPULP` | base + CORE-V XPULP |
| CFG_P_F0 / F1 / F2 | `RV32IMFC…_XPULP` | + FPU, FP latency 0 / 1 / 2 |
| CFG_P_Z0 / Z1 / Z2 | `RV32IMC_Zfinx…_XPULP` | + ZFINX FP, latency 0 / 1 / 2 |

(`COREV_CLUSTER=1` configs are explicitly **not verified**.) The simulation
regression is four test-lists run across all seven configs, each randomized test
up to 200 seeds (authoritative totals from the milestone `README.md`):

| Regress list (`cv32e40pv2_*`) | Distinct tests | Total runs (7 cfg) | Fail |
|-------------------------------|----------------|--------------------|------|
| `xpulp_instr` | 34 | 10 031 | 0 |
| `fpu_instr` | 10 | 9 024 | 0 |
| `interrupt_debug` (+ `_long`) | 27 (+14) | 13 408 | 3 (timeouts) |
| `legacy_v1` | 31 | 203 | 0 |
| **Total** | | **32 666** | **3** |

The three "failures" are time-outs (need a longer per-test budget), not
miscompares. **This — not our 25-test FAST2 `no_pulp` — is the real OVPSIM
workload GVSOC must eventually stand in for.** Our `no_pulp` suite is a
bring-up scaffold (base ISA + CV32E40P CSR/exception, XPULP off): the fastest path
to a green step-and-compare, but not an OpenHW sign-off configuration.

### 3.7 Migration scope — what GVSOC must run, and what it need not

GVSOC is a **simulation ISS reference model**: it replaces Imperas only in method
(2) above. It is not a formal tool and does not displace the Sail formal flow,
RISCOF, or the coverage sign-off. That bounds the target sharply.

**Must run on GVSOC — ISS-distinct behaviour:**

| Scope | Why GVSOC must cover it |
|-------|-------------------------|
| Base RV32IMC + Zicsr + CV32E40P CSR/exception | foundation; this is our `no_pulp` bring-up subset |
| **XPULP** (`xpulp_instr`, 34) | the CORE-V custom ISA — hardware loops, MAC, SIMD/vectorial, bit-manip, post-inc load/store. **This is the entire reason to use GVSOC over a generic ISS**: a stock RISC-V model cannot reproduce these |
| **FPU** (`fpu_instr`, 10) | F extension + ZFINX; GVSOC models FPnew |
| **Interrupt + Debug** (`interrupt_debug`, 27 +14) | architectural; this is exactly our currently-excluded / deadlocking set |

**Need NOT run on GVSOC — no ISS value; leave it to the RTL/formal sign-off:**

| Skipped | Why it adds nothing to ISS validation |
|---------|----------------------------------------|
| The Sail **formal** ISA proofs | a different method; stays as the primary instruction-correctness sign-off, GVSOC does not replace it |
| `COREV_CLUSTER` configs | OpenHW itself does not verify them |
| FP **latency variants** F1 / F2, Z1 / Z2 | they change only RTL pipeline *timing*; the architectural FP result GVSOC compares is latency-independent. One F + one Z config validate the ISS — the other four are RTL coverage, not ISS coverage |
| The full **200-seed / 32 666-run** sweep | that volume exists for RTL *coverage closure*; GVSOC needs enough seeds to exercise each behaviour, not seed-count parity. Coverage sign-off stays with OVPSIM (the stated migration intent) |
| Bulk of `legacy_v1` (31) | ~27 of its tests are the same base exception / CSR / arith / illegal tests already in `no_pulp`; only `coremark` / `matmul_*` are unique. Backward-compat regression, negligible new ISS coverage |

**Representative config set for full ISS parity: three —
`{CFG_P, CFG_P_F0, CFG_P_Z0}`** (which we already have as `pulp`, `pulp_fpu`,
`pulp_fpu_zfinx`). Everything ISS-distinct in the 7-config matrix is exercised by
these three; the remaining four are latency-timing replicas for RTL coverage.

---

## 4. ISS Fixes by Category

| Category | Count | Examples |
|----------|-------|----------|
| CSR modelling | ~15 | mstatus write-mask, misa, mtvec, mcause trap push |
| PULP ISA encoding | ~12 | CoreV2 vectorial, MAC, bit-manipulation |
| DPI bridge protocol | ~15 | trap timing, WFI watchdog, CSR snapshot, IRQ settle |
| Build / config | ~6 | Makefile ordering, JSON config, findstring fix |

Each fix is made at the root in the C++ ISS source rather than hidden behind a
`volatile`/`reconverge` workaround — the central maintainability argument for
GVSOC over a closed binary.

---

## 5. Solution Architecture

```
┌─────────────────────────────────────────────────┐
│ UVM testbench (uvmt_cv32e40p_tb.sv)             │
│   ├─ DUT (cv32e40p_top)                         │
│   ├─ RVFI monitor (uvma_rvfi_agent)             │
│   ├─ RVVI sync bridge (rvvi_trace2api)   │  ← GVSOC path
│   ├─ OVPSIM agent (uvma_rvvi_ovpsim)            │  ← Imperas path
│   └─ ISS wrap (gvsoc_wrap / imperas_dv_wrap)    │  ← selected by ISS=
├─────────────────────────────────────────────────┤
│ libgvsoc_rvvi.so  (rvvi_api2gvsoc.cpp + engine)    │
├─────────────────────────────────────────────────┤
│ GVSOC ISS C++ models (cores/cv32e40p, shared)    │
└─────────────────────────────────────────────────┘
```

Shared RVFI→RVVI wiring: `uvmt_cv32e40p_iss_wrap_common.svh` (included by both
wraps; the GVSOC wrap defines `RVVI_SET_TRAP_CSR`, the Imperas wrap falls back to
the inert default). Key files: `vendor_lib/gvsoc_rvvi/{rvvi_bridge,gvsoc_engine}.cpp`,
`cv32e40p/tb/uvmt/uvmt_cv32e40p_gvsoc_wrap.sv`,
`vendor_lib/gvsoc_rvvi/rvvi_trace2api.sv`.

---

## 6. Conclusion

On the FAST2 `no_pulp` subset GVSOC reaches **99.69% ISS-attributable parity**
with the OVPSIM reference, with cross-target build safety preserved. But the
honest gap to full Imperas-suite parity is three-part: one genuine ISS
divergence (`mepc`), a missing reconverge mechanism that causes 5 testbench
deadlocks, and 18 debug/interrupt tests excluded from FAST2 for DPI co-sim
trap/timing divergences. "Imperas = 100%" is golden-by-definition, not a measured
baseline; even Imperas curates out known miscompares.

But FAST2 `no_pulp` is only the bring-up gate. The real target (§3.6-3.7) is the
PULP-based simulation regression — XPULP, FPU and interrupt/debug on the
representative configs `{CFG_P, CFG_P_F0, CFG_P_Z0}` — since that, not `no_pulp`,
is what OVPSIM actually runs at sign-off. GVSOC does not need to reproduce the
Sail formal flow, the cluster configs, the FP-latency replicas, or the full
seed-count sweep: those stay with the RTL/formal/coverage sign-off.

For the migration plan from OVPSIM to GVSOC and the exact completion criteria,
see **`gvsoc_migration_roadmap.md`** in this directory.
