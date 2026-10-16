# CV32E40P GVSOC ISS Integration

This branch adds **GVSOC** as an open-source ISS reference model for CV32E40P
co-simulation, alongside the existing Imperas OVPSIM path. It is the
testbench-side counterpart of the upstream GVSOC PRs gvsoc-core#146,
gvsoc-pulp#74 and gvsoc#252.

## What this adds

- A DPI step-and-compare bridge (`rvvi_trace2api`) driving GVSOC over the
  standard RVVI interface, selected with `ISS=GVSOC`.
- A GVSOC reference-model wrap (`uvmt_cv32e40p_gvsoc_wrap`) built on the
  RVFI→RVVI wiring shared, unchanged in behaviour, with the Imperas wrap.
- Build/run integration (`USE_ISS=YES ISS=GVSOC`).
- The `gvsoc_rvvi` bridge as a submodule (embeds GVSOC, exposes it via the RVVI
  DPI API).

The Imperas path is untouched: it remains the default reference model
(`ISS ?= IMPERAS`); shared files change shape only behind `ifndef`-guarded macro
defaults, and the GVSOC-specific code is selected with `USE_GVSOC`.

## Status (verified) — read the framing, not just the number

Status as of 2026-08-18. The FAST2/`no_pulp` bring-up numbers this section used
to carry live in the git history; the PULP regression below is the real
OVPSIM-replacement scope, as classified in the report §3.6-3.7.

| What | Result |
|------|--------|
| Full PULP DPI co-sim regression, 7 TB configs (`pulp`, `pulp_fpu`, `pulp_fpu_zfinx`, each ± 1/2-cycle FPU latency), 413 lanes (2026-08-18) | **408 PASS, 3 known-fail, 2 explained artifacts — zero unexplained failures** |
| RISCOF vs the Sail golden model (rv32imc+F arch-tests, 434 tests) | **431/434 PASS, F extension 342/342**; the 3 residuals are a reference-configuration class (the reference's mtvec reset enters the signature), not ISS defects |
| Code coverage over the passing set, official v2 waivers only (the sign-off's own exclusion .do files, unmodified — apples-to-apples with the Imperas-era flow) | **bcs 99.16%** (statements 99.77 / branches 99.08 / conditions 98.63), assertions **100%** |
| Same, plus a full formal unreachability pass (Questa CoverCheck, 694 items proven unreachable — the "need to prove" step the official sign-off left open) | **bcs 99.36%** (statements 99.82 / branches 99.63 / conditions 98.63), FSM states **100%** — every residual item enumerated and risk-assessed |

**Honesty framing of the 5 non-PASS lanes.** The 3 known-fails are documented,
root-caused divergences carried in the xfail list, not silent waivers:
`debug_test` (a DUT-side RVFI tracer artifact on haltreq entries — see the
Debug entry section of `ARCHITECTURE.md`) and `interrupt_nested` on two configs
(the riscv-dv-emitted handler re-enables MIE with no depth bound, so the
generated program self-destructs by unbounded re-nesting — a generator
trajectory, not a model or RTL defect). The 2 explained artifacts are
observation-layer, both with zero ISS/RTL mismatches: a TB covergroup
illegal-bin that attributes trap-handler instructions to a hardware-loop body,
and a one-row `mstatus.FS` visibility skew on an FP load outside the
latency-aware compare window (both documented with proposed fixes). None of
this is a regression of the existing Imperas flow, which is unchanged.

## Where the detail lives

- **`gvsoc_vs_imperas_final_report.md`** — full GVSOC-vs-OVPSIM evaluation: what
  "Imperas baseline" means, the FAST2-vs-full suite asymmetry, the apples-to-
  apples analysis, per-failure classification, data provenance, and (§3.6-3.7)
  **how OpenHW actually runs the v1.8.3 regression** plus the migration-scope
  classification (what GVSOC must run vs what stays with the RTL/formal sign-off).
- **`gvsoc_migration_roadmap.md`** — the exact roadmap to complete the
  OVPSIM→GVSOC migration: the three parity tiers, the in-scope/out-of-scope
  classification, seven sprints (0-6), effort estimates, and the definition of
  "done".

## Open items before opening the upstream PR

1. The three ISS PRs (gvsoc-core#146 / gvsoc-pulp#74 / gvsoc#252) must land
   first — the bridge will not build from a clean clone until they do.
2. `gvsoc_rvvi` must be made public (the submodule points at it).
3. A fresh full FAST2 regression on the exact frozen ISS revision is the
   validation gate (roadmap Sprint 0).
