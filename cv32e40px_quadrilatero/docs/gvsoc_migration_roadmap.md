# CV32E40P: OVPSIM → GVSOC Migration Roadmap

Roadmap to complete the migration of the CV32E40P ISS reference model from
Imperas OVPSIM to the open-source GVSOC, and the exact criteria for calling the
work "done". Status as of 2026-06-15.

For the regression evidence and the apples-to-apples analysis behind these
numbers, see `gvsoc_vs_imperas_final_report.md` in this directory.

---

## The honest picture

There is **no measured Imperas baseline pass-count** in this repo: Imperas is
the reference model, so on the curated run subset it passes *by construction*
(the official count is produced on an external Metrics cloud). The migration is
therefore "GVSOC reaching the behaviour Imperas defines", and the gap is
measured by what GVSOC cannot yet step-and-compare cleanly.

The headline GVSOC figure — **644/651 (98.92%), 99.69% ISS-attributable** — is
measured on **FAST2** (25 tests), a subset of our `no_pulp` bring-up suite (43
active tests; the 18-test difference is debug/interrupt/ebreak/illegal-instr,
excluded *for GVSOC* due to DPI co-sim trap/timing divergences).

But `no_pulp` is **not** an OpenHW sign-off configuration. The official v1.8.3
RTL-freeze regression runs on **seven all-XPULP configs** (CFG_P + FPU/ZFINX
latency variants), and its simulation suite is **XPULP + FPU + interrupt/debug +
legacy**, ~32 666 randomized runs (see the evaluation report §3.6). So there are
three tiers, not two:

- **Bring-up gate** (FAST2 `no_pulp`): essentially reached — 1 ISS divergence + 5
  testbench deadlocks remain.
- **`no_pulp` full**: bring back the 18 debug/IRQ tests (fix or classify).
- **Real OVPSIM replacement** (PULP target): step-and-compare clean on XPULP, FPU
  and interrupt/debug across the representative configs `{CFG_P, CFG_P_F0,
  CFG_P_Z0}` = our `pulp`, `pulp_fpu`, `pulp_fpu_zfinx`. This is the actual goal.

---

## Scope — what GVSOC must replace, and what it need not

OpenHW signs off v1.8.3 with **four methods**: RISC-V ISA **formal** (Sail,
primary), **simulation** regression (only for what formal can't model — hwloops,
prefetch/fetch, interrupt/debug), **RISCOF**, and **coverage**. GVSOC is a
*simulation* ISS reference — it replaces Imperas in the simulation path only.
That bounds the work:

**In scope (GVSOC must step-and-compare cleanly):**

- Base RV32IMC + Zicsr + CV32E40P CSR/exception — the `no_pulp` bring-up subset.
- **XPULP** (`xpulp_instr`, 34 tests) — hwloops, MAC, SIMD/vectorial, bit-manip,
  post-inc load/store. The reason GVSOC exists: a generic ISS cannot model these.
- **FPU** (`fpu_instr`, 10) — F + ZFINX.
- **Interrupt/Debug** (`interrupt_debug`, 27 +14) — our current gap.

**Out of scope (no ISS value — stays with the RTL/formal sign-off):**

- The **Sail formal** ISA proofs — different method, not GVSOC's to replace.
- `COREV_CLUSTER` configs — OpenHW does not verify them.
- FP **latency variants** F1/F2, Z1/Z2 — RTL pipeline timing only; the
  architectural result GVSOC compares is latency-independent, so one F + one Z
  suffice. The other four are RTL coverage.
- The full **200-seed / 32 666-run sweep** — coverage closure, not ISS validation;
  OVPSIM stays golden for coverage sign-off.
- Bulk of **`legacy_v1`** — ~27/31 are base tests already in `no_pulp`; only
  `coremark` / `matmul_*` are unique.

**Representative config set: three — `{CFG_P, CFG_P_F0, CFG_P_Z0}`.**

---

## Current status

| Component | State | What is left |
|-----------|-------|--------------|
| GVSOC ISS core model (arith / CSR / ISA, `no_pulp`) | Production-ready | one `mepc` divergence (`generic_exception_test`) |
| GVSOC on debug/interrupt suite | **Not at parity** | 18 FAST2-excluded tests (trap/timing divergences) |
| GVSOC on XPULP + FPU (PULP configs) | **Not yet run at suite scale** | `xpulp_instr` (34) + `fpu_instr` (10) on `{CFG_P, CFG_P_F0, CFG_P_Z0}` — Sprint 4 |
| DPI bridge (SV ↔ ISS) | Working, no reconverge | no mismatch-timeout / reconverge → 5 deadlocks |
| DPI co-sim performance | Slow | DPI step-and-compare adds ~15-116x over RTL-only sim |
| Cross-target safety | Preserved | all non-CV32E40P targets build (287 `.so`) |
| Upstream PRs (ISS side) | In review | Germain review on gvsoc-core#146 / gvsoc-pulp#74 / gvsoc#252 |
| Testbench branch (this repo) | Prepared | `mpaci/cv32e40p-pr-upstream`, not yet opened |

Headline regression (FAST2 `no_pulp`, last full run 2026-05-20): **644/651 PASS
(98.92%)**, **99.69% ISS-attributable**.

---

## The roadmap

Effort estimates are calendar days for one engineer. Severity: P0 blocks the
migration, P1 is required for full-suite "ship-ready", P2/P3 are quality.

### Sprint 0 — Freeze the ISS and land the PRs  ·  P0  ·  in progress

The GVSOC ISS is frozen (gvsoc-core `22216971`, gvsoc-pulp `9d9835a`, outer
gvsoc `2b40cd7`). The three upstream PRs were force-pushed and commented on
2026-06-12; they await Germain's review.

- [x] Freeze ISS revision; cross-target build GREEN; strip-check vs upstream PASS
- [x] gvsoc-core#146 / gvsoc-pulp#74 / gvsoc#252 refreshed + comments posted
- [x] Testbench integration branch prepared (`mpaci/cv32e40p-pr-upstream`, 8 commits)
- [ ] Respond to Germain's review feedback and land the three ISS PRs
- [ ] **Fresh full FAST2 regression on the exact frozen revision** (validation gate)
- [ ] Open the testbench PR once the ISS PRs land and `gvsoc_rvvi` is public

**Gate / exit:** three ISS PRs merged; a fresh full FAST2 run on the frozen
revision reproduces ≥99.6% ISS-attributable. (The 644/651 is from 2026-05-20 on
behaviourally-equivalent code; this run has not yet been done.)

### Sprint 1 — `generic_exception_test` `mepc` divergence  ·  P1  ·  1–3 days

The one genuine ISS-attributable functional FAIL on FAST2. `mepc` (CSR 0x341)
diverges at retire #538 (10 consecutive PC mismatches) on a trap-handling path.

- [ ] Diagnose the `mepc` mismatch (gvsoc-debugger)
- [ ] Decide: ISS fix vs bridge fix vs documented known divergence
- [ ] If fixable: ship, smoke-test, commit to the downstream bridge

**Exit:** the only FAST2 ISS-attributable FAIL is resolved or formally
classified as a known divergence.

### Sprint 2 — Bridge reconverge / mismatch-timeout  ·  P1  ·  3–5 days

The 5 FAST2 deadlocks all share one root cause: the GVSOC sync bridge has **no
reconverge-on-mismatch and no consecutive-mismatch timeout**, where the Imperas
wrap has `ON_MISMATCH_RECONVERGE`. On a *sustained* CSR mismatch GVSOC hangs
(hours of wall-clock) instead of failing fast. This is the structural asymmetry
between the two reference-model paths.

- [ ] Add a consecutive-mismatch counter in `rvvi_trace2api.sv`
- [ ] Configurable threshold (e.g. 100 consecutive mismatches → `UVM_FATAL`)
- [ ] (stretch) evaluate a reconverge-equivalent to keep running past a mismatch
- [ ] Smoke + targeted regression

**Exit:** the 5 deadlocks become controlled `UVM_FATAL` failures (diagnosable in
minutes, not hours), unblocking unattended CI on the full suite.

### Sprint 3 — Interrupt / debug parity  ·  P1  ·  10–20 days

The 18 tests excluded from FAST2 (debug/interrupt/ebreak/illegal-instr) and the
PULP `interrupt_debug` group (27 +14 tests, the largest simulation group at
13 408 runs) share one root cause: DPI co-sim trap/timing divergences
(ebreak→breakpoint pipeline-stage timing, `mscratch` sp-swap handler convention,
random interrupt/debug trap nesting). Fixing it here unblocks both the `no_pulp`
full suite and the PULP interrupt/debug group.

- [ ] Run GVSOC on the full 43-test `no_pulp` suite once Sprint 2 stops the hangs
- [ ] Triage each divergence: GVSOC ISS fix vs DPI-path fix vs documented known divergence
- [ ] Re-enable every fixed test; publish a known-divergence list for upstream readers

**Exit:** the `no_pulp` full suite runs clean and interrupt/debug behaviour is
validated (the same path the PULP `interrupt_debug` group exercises).

### Sprint 4 — XPULP + FPU parity on the PULP configs (the real OVPSIM target)  ·  P1  ·  15–30 days

This is the **actual OVPSIM replacement**: the OpenHW sign-off is PULP-based and
its differentiating coverage is XPULP + FPU. GVSOC's CoreV2 model already
implements ~12 PULP ISA encodings and FPnew; this sprint validates them at suite
scale, on the three representative configs only.

- [ ] `pulp` (CFG_P): run `xpulp_instr` (34 — hwloop, MAC, SIMD/vectorial,
      bit-manip, post-inc) → triage CoreV2 ISA divergences
- [ ] `pulp_fpu` (CFG_P_F0): run `fpu_instr` (10) → triage FP/rounding (known
      gaps: round-to-nearest-max-magnitude, NaN-boxing)
- [ ] `pulp_fpu_zfinx` (CFG_P_Z0): run `fpu_instr` → triage ZFINX interaction
- [ ] Skip the F1/F2, Z1/Z2 latency replicas (RTL coverage, no ISS value)

**Exit:** GVSOC step-and-compares cleanly on `{CFG_P, CFG_P_F0, CFG_P_Z0}` for
XPULP + FPU + interrupt/debug — every ISS-distinct behaviour OpenHW signs off.
This is "GVSOC replaces OVPSIM for simulation step-and-compare".

### Sprint 5 — DPI co-simulation performance  ·  P3  ·  10–30 days

GVSOC DPI runs at ~20-60 retires/s. Adding the DPI step-and-compare makes the
simulation ~15-116x slower than RTL-only (measured 2026-03-26: hello-world 45x,
dhrystone 15x, riscv_ebreak 116x). This is the cost of the co-simulation, not a
GVSOC-vs-OVPSIM comparison: we have no OVPSIM throughput measurement (OVPSIM runs
on the external Metrics cloud, not locally). The FAST2 wall-clock was ~12 h.

- [ ] Graduated stepping back-off: +12-18% throughput
- [ ] Kernel-level step loop: +20-35% throughput
- [ ] Pure-DPI function audit: +5-10%

**Exit:** 30–50% speed-up (full-suite regression in hours, not half a day).

### Sprint 6 — Production ramp (coverage cross-check optional)  ·  P2  ·  5–10 days

Coverage sign-off stays with OVPSIM (the migration intent), so this sprint is
about adoption, not coverage parity.

- [ ] Production ramp: substitute GVSOC for OVPSIM in fast-iteration CI, OVPSIM
      retained as golden for the coverage sign-off
- [ ] (optional) UCDB coverage merge: GVSOC-vs-OVPSIM gap analysis, only if GVSOC
      is later asked to also drive coverage

**Exit:** GVSOC adopted for CI fast iteration; OVPSIM remains the golden ISS for
coverage sign-off.

---

## Effort summary

| Sprint | Min | Max | Severity |
|--------|-----|-----|----------|
| 0 — Freeze + PR landing | 1 d | (review-bound) | P0 (in progress) |
| 1 — `mepc` fix | 1 d | 3 d | P1 |
| 2 — bridge reconverge/timeout | 3 d | 5 d | P1 |
| 3 — interrupt/debug parity | 10 d | 20 d | P1 |
| 4 — XPULP + FPU parity (PULP target) | 15 d | 30 d | P1 |
| 5 — performance | 10 d | 30 d | P3 |
| 6 — production ramp (coverage optional) | 5 d | 10 d | P2 |
| **Total** | **~45 d** | **~108 d** | |

---

## Definition of "done"

**Fast-CI ship-ready** (the near-term, mostly reached):

1. ✅ Cross-target safety — no other GVSOC core is broken.
2. ⏳ Three ISS PRs merged upstream with Germain's review accepted.
3. ⏳ FAST2 ISS-attributable pass rate ≥99.85% (after the `mepc` fix) and no
   suite hangs (after the reconverge/timeout work).

**Full OVPSIM replacement** (the complete migration):

4. ⏳ GVSOC runs the **full 43-test `no_pulp` suite** (not just FAST2), with the
   18 debug/interrupt tests either passing or in a published known-divergence
   list.
5. ⏳ GVSOC step-and-compares cleanly on the **PULP target** — XPULP + FPU +
   interrupt/debug on `{CFG_P, CFG_P_F0, CFG_P_Z0}` (the ISS-distinct subset of
   the OpenHW sign-off configs).
6. ⏳ DPI performance >100 retires/s (cut the ~15-116x co-sim overhead over RTL-only).

**Explicitly out of scope** (stays with the RTL/formal/coverage sign-off): the
Sail formal ISA flow, the `COREV_CLUSTER` configs, the FP-latency config replicas
(F1/F2, Z1/Z2), the full 200-seed / 32 666-run coverage sweep, and the redundant
bulk of `legacy_v1`. OVPSIM remains the golden ISS for coverage sign-off.

Items 1–3 make GVSOC a functional alternative to OVPSIM for fast-iteration CI.
Items 4–6 make it a true simulation-path replacement on the configurations that
exercise ISS-distinct behaviour.
