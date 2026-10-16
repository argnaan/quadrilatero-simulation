/*
**
** Copyright 2026 OpenHW Group
**
** Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
** you may not use this file except in compliance with the License.
** You may obtain a copy of the License at
**
**     https://solderpad.org/licenses/
**
** Unless required by applicable law or agreed to in writing, software
** distributed under the License is distributed on an "AS IS" BASIS,
** WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
** See the License for the specific language governing permissions and
** limitations under the License.
**
** SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
**
*******************************************************************************
**
** HPM counter CSR decoder case-arm access test
**
** Touches EVERY performance-counter CSR address (read AND write):
**   - mhpmcounter3..31    (0xB03-0xB1F)
**   - mhpmcounter3h..31h  (0xB83-0xB9F)
**   - mhpmevent3..31      (0x323-0x33F)
**   - mcycle/minstret + H (0xB00/0xB02/0xB80/0xB82)
**   - mcountinhibit       (0x320) WARL boundary
** and exercises the mhpmcounter3 event-driven increment path.
**
** Target: CV32E40P with NUM_MHPMCOUNTERS = 1 (TB default,
** uvmt_cv32e40p_tb.sv:98). RTL contract (cv32e40p v1.8.3,
** core-v-cores/cv32e40p/rtl):
**   - The decoder marks ALL these addresses as legal M-mode CSRs
**     (cv32e40p_decoder.sv:2826-2856) - no illegal-instruction trap.
**   - Non-implemented counters/events (index 4..31 with NUM=1) read as
**     zero and ignore writes: mhpmcounter_q tied to 0
**     (cv32e40p_cs_registers.sv:1461-1462), mhpmevent_q tied to 0
**     (cv32e40p_cs_registers.sv:1489-1490).
**   - mhpmevent3 implements only 16 event lines: bits [31:16] read 0
**     (cv32e40p_cs_registers.sv:142,1492-1494).
**   - mcountinhibit implements only bits 0 (CY), 2 (IR), 3 (HPM3);
**     others read 0 (cv32e40p_cs_registers.sv:1524-1526). Reset value
**     0xD = all implemented counters inhibited
**     (cv32e40p_cs_registers.sv:1529).
**
** Co-simulation notes (GVSOC ISS is the strong checker at retire):
**   - CY (mcountinhibit[0]) is NEVER cleared: GVSOC is not
**     cycle-accurate, a free-running mcycle would diverge.
**   - IR (mcountinhibit[2]) is NEVER cleared: sidesteps the
**     mcountinhibit enable-boundary semantics on minstret (the write
**     to mcountinhibit is gated by the PRE-write value; see finding
**     2026-08-17). Only HPM3 (bit 3) is toggled, with the
**     retired-instruction event, which both sides model identically.
**   - All exact self-checks run with the involved counter inhibited.
**
** No FP instructions: runs unmodified on pulp / pulp_fpu /
** pulp_fpu_zfinx configurations.
**
*******************************************************************************
*/

#include <stdio.h>
#include <stdlib.h>

static int err_cnt = 0;

static void check_eq(const char *tag, unsigned int got, unsigned int exp)
{
  if (got != exp) {
    printf("FAIL: %s = 0x%x, expected 0x%x\n", tag, got, exp);
    err_cnt++;
  }
}

/* CSR address must be a compile-time literal inside the asm string. */
#define CSR_READ(csr, dst)  __asm__ volatile("csrr %0, " #csr : "=r"(dst))
#define CSR_WRITE(csr, val) __asm__ volatile("csrrw x0, " #csr ", %0" : : "r"(val))

/* Non-implemented HPM CSR (NUM_MHPMCOUNTERS=1): reads 0, ignores writes.
 * Read first (hits the decoder case-arm + read mux with the reset value),
 * then write all-ones and read back 0 (write path is a no-op). */
#define CHECK_TIED_ZERO(csr) do {                  \
    unsigned int rb_;                              \
    CSR_READ(csr, rb_);                            \
    check_eq(#csr " reset-read", rb_, 0u);         \
    CSR_WRITE(csr, 0xFFFFFFFFu);                   \
    CSR_READ(csr, rb_);                            \
    check_eq(#csr " write-noop", rb_, 0u);         \
} while (0)

/* Implemented counter register, checked under stable inhibit: write a
 * pattern, read back exactly. */
#define CHECK_RW_EXACT(csr, pat) do {              \
    unsigned int rb_;                              \
    CSR_WRITE(csr, (pat));                         \
    CSR_READ(csr, rb_);                            \
    check_eq(#csr " rw-exact", rb_, (pat));        \
} while (0)

int main(int argc, char *argv[])
{
  unsigned int rb;

  (void)argc;
  (void)argv;

  printf("cv32e40p_hpm_counter_access_test start\n");

  /*************************************************************************
   * Phase 0 - reset state.
   * crt0.S only writes mtvec, so at main() entry the HPM bank still holds
   * its reset state: mcountinhibit = 0xD (CY|IR|HPM3 inhibited,
   * cv32e40p_cs_registers.sv:1529), every counter/event register = 0.
   *************************************************************************/
  CSR_READ(0x320, rb); check_eq("mcountinhibit reset", rb, 0xDu);
  CSR_READ(0xB00, rb); check_eq("mcycle reset",        rb, 0u);
  CSR_READ(0xB02, rb); check_eq("minstret reset",      rb, 0u);
  CSR_READ(0xB80, rb); check_eq("mcycleh reset",       rb, 0u);
  CSR_READ(0xB82, rb); check_eq("minstreth reset",     rb, 0u);
  CSR_READ(0xB03, rb); check_eq("mhpmcounter3 reset",  rb, 0u);
  CSR_READ(0xB83, rb); check_eq("mhpmcounter3h reset", rb, 0u);
  CSR_READ(0x323, rb); check_eq("mhpmevent3 reset",    rb, 0u);

  /*************************************************************************
   * Phase 1 - full sweep of the NON-implemented HPM addresses (idx 4..31).
   * Each macro does: read (expect 0), write 0xFFFFFFFF, read (expect 0).
   * This closes the decoder case-arm branches at
   * cv32e40p_decoder.sv:2829-2835 (mhpmcounter4..31) and :2839-2845
   * (mhpmcounter4h..31h), plus the mhpmevent4..31 arms (:2848-2854).
   *************************************************************************/
  printf("Phase 1: non-implemented counter sweep (0xB04-0xB1F)\n");
  CHECK_TIED_ZERO(0xB04); CHECK_TIED_ZERO(0xB05); CHECK_TIED_ZERO(0xB06);
  CHECK_TIED_ZERO(0xB07); CHECK_TIED_ZERO(0xB08); CHECK_TIED_ZERO(0xB09);
  CHECK_TIED_ZERO(0xB0A); CHECK_TIED_ZERO(0xB0B); CHECK_TIED_ZERO(0xB0C);
  CHECK_TIED_ZERO(0xB0D); CHECK_TIED_ZERO(0xB0E); CHECK_TIED_ZERO(0xB0F);
  CHECK_TIED_ZERO(0xB10); CHECK_TIED_ZERO(0xB11); CHECK_TIED_ZERO(0xB12);
  CHECK_TIED_ZERO(0xB13); CHECK_TIED_ZERO(0xB14); CHECK_TIED_ZERO(0xB15);
  CHECK_TIED_ZERO(0xB16); CHECK_TIED_ZERO(0xB17); CHECK_TIED_ZERO(0xB18);
  CHECK_TIED_ZERO(0xB19); CHECK_TIED_ZERO(0xB1A); CHECK_TIED_ZERO(0xB1B);
  CHECK_TIED_ZERO(0xB1C); CHECK_TIED_ZERO(0xB1D); CHECK_TIED_ZERO(0xB1E);
  CHECK_TIED_ZERO(0xB1F);

  printf("Phase 1: non-implemented counterh sweep (0xB84-0xB9F)\n");
  CHECK_TIED_ZERO(0xB84); CHECK_TIED_ZERO(0xB85); CHECK_TIED_ZERO(0xB86);
  CHECK_TIED_ZERO(0xB87); CHECK_TIED_ZERO(0xB88); CHECK_TIED_ZERO(0xB89);
  CHECK_TIED_ZERO(0xB8A); CHECK_TIED_ZERO(0xB8B); CHECK_TIED_ZERO(0xB8C);
  CHECK_TIED_ZERO(0xB8D); CHECK_TIED_ZERO(0xB8E); CHECK_TIED_ZERO(0xB8F);
  CHECK_TIED_ZERO(0xB90); CHECK_TIED_ZERO(0xB91); CHECK_TIED_ZERO(0xB92);
  CHECK_TIED_ZERO(0xB93); CHECK_TIED_ZERO(0xB94); CHECK_TIED_ZERO(0xB95);
  CHECK_TIED_ZERO(0xB96); CHECK_TIED_ZERO(0xB97); CHECK_TIED_ZERO(0xB98);
  CHECK_TIED_ZERO(0xB99); CHECK_TIED_ZERO(0xB9A); CHECK_TIED_ZERO(0xB9B);
  CHECK_TIED_ZERO(0xB9C); CHECK_TIED_ZERO(0xB9D); CHECK_TIED_ZERO(0xB9E);
  CHECK_TIED_ZERO(0xB9F);

  printf("Phase 1: non-implemented event sweep (0x324-0x33F)\n");
  CHECK_TIED_ZERO(0x324); CHECK_TIED_ZERO(0x325); CHECK_TIED_ZERO(0x326);
  CHECK_TIED_ZERO(0x327); CHECK_TIED_ZERO(0x328); CHECK_TIED_ZERO(0x329);
  CHECK_TIED_ZERO(0x32A); CHECK_TIED_ZERO(0x32B); CHECK_TIED_ZERO(0x32C);
  CHECK_TIED_ZERO(0x32D); CHECK_TIED_ZERO(0x32E); CHECK_TIED_ZERO(0x32F);
  CHECK_TIED_ZERO(0x330); CHECK_TIED_ZERO(0x331); CHECK_TIED_ZERO(0x332);
  CHECK_TIED_ZERO(0x333); CHECK_TIED_ZERO(0x334); CHECK_TIED_ZERO(0x335);
  CHECK_TIED_ZERO(0x336); CHECK_TIED_ZERO(0x337); CHECK_TIED_ZERO(0x338);
  CHECK_TIED_ZERO(0x339); CHECK_TIED_ZERO(0x33A); CHECK_TIED_ZERO(0x33B);
  CHECK_TIED_ZERO(0x33C); CHECK_TIED_ZERO(0x33D); CHECK_TIED_ZERO(0x33E);
  CHECK_TIED_ZERO(0x33F);

  /*************************************************************************
   * Phase 2 - implemented registers, exact write/read-back while their
   * counters are inhibited (mcountinhibit still 0xD from reset).
   * Writing 0xB83 exercises the mhpmcounter_write_upper path
   * (cv32e40p_cs_registers.sv:1416-1417,1473-1474; MHPMCOUNTER_WIDTH=64,
   * cv32e40p_pkg.sv:593).
   *************************************************************************/
  printf("Phase 2: implemented registers exact rw\n");
  CHECK_RW_EXACT(0xB03, 0xA5A5A5A5u);   /* mhpmcounter3  */
  CHECK_RW_EXACT(0xB83, 0x5A5A5A5Au);   /* mhpmcounter3h */
  CHECK_RW_EXACT(0xB00, 0x11111111u);   /* mcycle    (CY inhibited) */
  CHECK_RW_EXACT(0xB80, 0x22222222u);   /* mcycleh   (CY inhibited) */
  CHECK_RW_EXACT(0xB02, 0x33333333u);   /* minstret  (IR inhibited) */
  CHECK_RW_EXACT(0xB82, 0x44444444u);   /* minstreth (IR inhibited) */

  /* mhpmevent3 WARL: only 16 event lines exist, bits [31:16] read 0. */
  CSR_WRITE(0x323, 0xFFFFFFFFu);
  CSR_READ(0x323, rb); check_eq("mhpmevent3 WARL", rb, 0xFFFFu);

  /*************************************************************************
   * Phase 3 - mcountinhibit WARL boundary: only bits 0,2,3 are
   * implemented. Writing all-ones keeps every counter inhibited (safe)
   * and must read back 0xD. csrrsi exercises the SET op on the same
   * address (still no state change: implemented bits already set).
   *************************************************************************/
  printf("Phase 3: mcountinhibit WARL boundary\n");
  CSR_WRITE(0x320, 0xFFFFFFFFu);
  CSR_READ(0x320, rb); check_eq("mcountinhibit WARL", rb, 0xDu);
  __asm__ volatile("csrrsi x0, 0x320, 0x1F");
  CSR_READ(0x320, rb); check_eq("mcountinhibit csrrsi", rb, 0xDu);

  /*************************************************************************
   * Phase 4 - event-driven increment of mhpmcounter3 (closes the
   * write_increment branch, cv32e40p_cs_registers.sv:1475-1476, for the
   * one implemented HPM counter).
   * Event line 1 = retired instructions (cv32e40p_cs_registers.sv:1328).
   * Only bit 3 of mcountinhibit is toggled; CY/IR stay set.
   * Enable/disable writes use the immediate SET/CLEAR forms; the
   * enabling csrrci itself does not count (gated by the pre-write
   * inhibit value), the 8 nops and the disabling csrrsi do:
   * expected count = 9 exactly, self-checked with a robust window.
   *************************************************************************/
  printf("Phase 4: mhpmcounter3 event counting\n");
  CSR_WRITE(0x323, 0x2u);               /* mhpmevent3 = retired-instr line */
  CSR_WRITE(0xB03, 0u);
  CSR_WRITE(0xB83, 0u);
  __asm__ volatile("csrrci x0, 0x320, 0x8");   /* enable HPM3 only  */
  __asm__ volatile("nop\n\t" "nop\n\t" "nop\n\t" "nop\n\t"
                   "nop\n\t" "nop\n\t" "nop\n\t" "nop");
  __asm__ volatile("csrrsi x0, 0x320, 0x8");   /* inhibit HPM3 again */
  CSR_READ(0xB03, rb);
  if (rb < 8u || rb > 32u) {
    printf("FAIL: mhpmcounter3 counted 0x%x, expected in [8,32]\n", rb);
    err_cnt++;
  }
  CSR_READ(0xB83, rb); check_eq("mhpmcounter3h after count", rb, 0u);

  /*************************************************************************
   * Cleanup - leave a benign, reset-like state.
   *************************************************************************/
  CSR_WRITE(0x320, 0xFFFFFFFFu);        /* everything inhibited (reads 0xD) */
  CSR_WRITE(0x323, 0u);
  CSR_WRITE(0xB03, 0u); CSR_WRITE(0xB83, 0u);
  CSR_WRITE(0xB00, 0u); CSR_WRITE(0xB80, 0u);
  CSR_WRITE(0xB02, 0u); CSR_WRITE(0xB82, 0u);

  if (err_cnt) {
    printf("FAILURE. %d errors\n", err_cnt);
  } else {
    printf("SUCCESS\n");
  }
  return err_cnt;
}
