# GVSOC ISS — Verification-Plan Parity Audit vs ImperasDV

**Data**: 2026-08-12 · **Ambito**: CV32E40Pv2 simulation sign-off (metodo 2 dei 4 metodi
del milestone v1.8.3: simulazione con reference model) · **Revisione ISS**: core `9f275f6f` /
pulp `66b648a` / gvsoc `3401620` / gvsoc_rvvi `f2a6adc` / cvv `2b9d33a1d` ·
**Evidenza**: quick_val full gate 2026-08-11 — **155 PASS / 0 FAIL / 3 known-fail / 2 skip**
(`/data2/marco.paci/validation-evidence/quickval_gate_20260811_c2/`).

## Verdetto (BLUF)

La co-simulazione GVSOC copre **tutti i punti di verifica che l'ambiente copriva con
ImperasDV**, con **2 sole eccezioni azionabili**, entrambe **chiuse il 2026-08-12**: lane
`load_store_rs1_zero` aggiunta e PASS; lane `all_csr_por` aggiunta, divergenza
root-caused (banca PMP dichiarata dal modello generico, assente nell'RTL) e
**fixata spec-driven** — la sweep CSR completa ora PASSA. **Matrice 427/427,
tutte expected-pass.** A livello di vplan-item, **661/785 item** dei piani di simulazione
v2 sono coperti dal nostro step-and-compare (648 pieni + 13 con chiusura bin rimandata
all'asse UCDB); i restanti 124 sono item che **nemmeno ImperasDV copriva**
(assertion RTL, item mai implementati upstream, N/A, TBD upstream, cluster).

## Metodo e fonti

- **Fonte di verità test-level**: `VerifPlans/Simulation/CV32E40Pv2_test_list.xlsx`
  (matrice ufficiale test × 7 configurazioni, con test_cfg per cella).
- **Fonte item-level**: i 14 vplan xlsx di `VerifPlans/Simulation/` (interrupts, debug,
  external-debugger, F/Zfinx, FPU regfile, OBI, Pipeline/Sleep, 7 XPULP).
- **Nostro sistema**: `vendor_lib/gvsoc_rvvi/test/quick_val.sh` — 160 lane su 4 config
  (`default`, `pulp`, `pulp_fpu`, `pulp_fpu_zfinx`), verdetti dal gate 2026-08-11.
- **Policy configurazioni** (da `gvsoc_vs_imperas_final_report.md` §3.7): il confronto ISS
  usa le 3 config rappresentative {CFG_P→`pulp`, CFG_P_F0→`pulp_fpu`, CFG_P_Z0→`pulp_fpu_zfinx`}.
  Le 4 varianti di latenza FPU (F1/F2/Z1/Z2) cambiano solo il timing RTL, non lo stato
  architetturale confrontato dal reference model. Il volume seed (fino a 200/test nel
  sign-off cloud) è chiusura di coverage RTL, non validazione ISS: fuori perimetro.
- L'ISA base RV32IMC+F+Zicsr è firmata dal **formale** (Sail + Questa Processor), non da
  ImperasDV: fuori perimetro di questo audit (resta col flusso formale).

## Livello A — test-list: 427 punti (test × config su P/F0/Z0)

| Classe | Punti | Significato |
|--------|-------|-------------|
| A — lane stessa config | 94 | lane quick_val identica (test+test_cfg+config), **tutte PASS** |
| B — variante stessa config | 19 | lane con stesso programma e test_cfg sovrainsieme/equivalente |
| C1 — directed rappresentativa | 141 | programma direct identico eseguito in config rappresentativa |
| C2 — FP-random rappresentata | 153 | l'asse FP-random è coperto dalle lane `corev_rand_fp_instr_*` dedicate |
| C3 — config rappresentativa | 14 | asse XPULP coperto dalle varianti dedicate (`*_xpulp`, famiglia hwloop) |
| **GAP — assente** | **6** | **`all_csr_por` e `load_store_rs1_zero` × 3 config** |

Dettaglio completo: foglio `GVSOC_parity_matrix` in `CV32E40Pv2_test_list_GVSOC.xlsx`
e CSV in `/data2/marco.paci/validation-evidence/vplan_parity_20260812/`.

Note sui gap:
- `all_csr_por`: il commento nel sorgente dichiara il rischio di miscompare col RM
  ("Step-and-compare against RM mismatch") — era problematico anche sotto Imperas.
  Da aggiungere come lane (eventualmente xfail caratterizzata al primo run).
- `load_store_rs1_zero`: assembly semplice, nessuna ragione nota di divergenza — lane `run` diretta.
- Nota inversa (a nostro favore): `debug_test_known_miscompares` sotto Imperas girava con
  il confronto disabilitato (`iss: 0`); con GVSOC gira **con confronto attivo e PASS**.

## Livello B — vplan-item: 785 item nei 14 piani di simulazione

| Verdetto | Item | Significato |
|----------|------|-------------|
| **COVERED-GVSOC** | **648** | correttezza verificata dal nostro step-and-compare sui test nominati dall'item |
| **COVERED-CG** | **13** | correttezza dal RM ok; la *chiusura dei bin* (bit-toggle/occorrenza) è l'asse UCDB — roadmap F1 |
| NON-ISS (assertion/covergroup RTL) | 41 | verificati da assertion/CG del testbench, identici con qualunque RM |
| NOT-CODED-UPSTREAM | 17 | vplan external-debugger: "Not yet coded" — mai coperti, nemmeno con Imperas |
| N/A | 59 | dichiarati N/A nel vplan originale |
| N/A-UPSTREAM-TBD | 4 | item lasciati TBD/senza sign-off upstream |
| N/A-CLUSTER | 1 | `cv.elw` richiede COREV_CLUSTER (config esplicitamente non verificata upstream) |
| separatori | 2 | righe "END" dei fogli |

Per-vplan: XPULP (bitmanip 48, ALU 80, MAC 36, SIMD 174, post-inc 72, imm-branch 6,
hwloop 34) tutti coperti; interrupts 63 coperti + 12 assertion + 8 N/A + 1 cluster;
debug 55 coperti + 18 assertion + 22 N/A/TBD; F/Zfinx 79 coperti; FPU regfile 5;
OBI e Pipeline/Sleep interamente assertion/N-A (non-ISS).

## Documenti aumentati (deliverable)

Ogni vplan ha ora un gemello `*_GVSOC.xlsx` nella stessa directory con 3 colonne
aggiunte accanto al tracciamento originale — **GVSOC ISS Status**, **GVSOC Witness**
(lane [config] verdetto gate), **GVSOC Note** — più un foglio `GVSOC_provenance`
(revisione ISS, evidenza, policy). `CV32E40Pv2_test_list_GVSOC.xlsx` aggiunge le colonne
di stato per le 3 config rappresentative e il foglio `GVSOC_parity_matrix` (427 punti).
I file originali non sono toccati.

## Azioni

1. ~~Aggiungere 2 lane a quick_val~~ **FATTO 2026-08-12**: `load_store_rs1_zero`
   (run, pulp) **PASS** al primo run (28 s). `all_csr_por` (pulp): la divergenza al
   retire #1.158.407 è stata **root-caused e fixata** — il DUT trappa illegal su
   `pmpcfg0` (CV32E40P non ha PMP), mentre il modello generico dichiara la banca
   PMP anche con la variante PmpEmpty (`CONFIG_GVSOC_ISS_PMP` è un nome di tipo,
   sempre definito). Fix spec-driven nella personality (`Cv32e40pCsr`: undeclare
   `pmpcfg0..15`/`pmpaddr0..63`, file cv32e40p-only, zero impatto cross-target).
   Validazione: sweep CSR completa **PASS** (2212 s, zero mismatch) + non-regressione
   `cv32e40p_csr_access_test`/`modeled_csr_por`/`readonly` PASS + smoke hello-world.
   Evidenza: `/data2/marco.paci/validation-evidence/{parity_lanes,pmp_fix_val}_20260812/`.
   **Matrice test-level: 427/427 punti, tutti expected-pass.**
2. **Asse UCDB (roadmap F1)**: i 13 item COVERED-CG chiudono i bin con la regressione
   COV=YES — già pianificata, indipendente dalla parity ISS.
3. ~~Correggere il claim stale nell'header di `quick_val.sh`~~ **FATTO 2026-08-12**
   (fix (5) ora descrive il meccanismo model-side post-consolidamento).

## Audit trail

Machine-readable: `/data2/marco.paci/validation-evidence/vplan_parity_20260812/`
(`levelA_verdict.{csv,json}`, `levelB_final.{csv,json}`, `levelA.json` con lane e matrice).
Generatori negli script di sessione (estrazione xlsx con espansione merge, join yaml/lane/gate).
