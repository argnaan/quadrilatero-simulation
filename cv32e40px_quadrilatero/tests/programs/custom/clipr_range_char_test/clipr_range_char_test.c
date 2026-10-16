/**
 * Test: characterize cv.clipr behavior with negative rs2 (degenerate range)
 *
 * Purpose: empirically measure RTL behavior of cv.clipr on edge cases where
 * rs2 is negative. The library clip logic assumes rs2 non-negative; behavior
 * on degenerate inputs (low > high) diverges between ISS and RTL observation.
 *
 * Test cases:
 *   1. rs2=0x93130db0 (negative), rs1=0x0000ffff - reproduces co-sim divergence
 *   2. rs2=0x80000000 (min int32), rs1={0, 1, -1}
 *   3. rs2=0xffffffff (-1), rs1={0, 5, -5}
 *   4. rs2=0x00000000, rs1={-2, -1, 0, 1, 2} - degenerate: low=-1, high=0
 *   5. Control: rs2=0x0f, rs1={-1, 8, 15, 16} - normal bounds
 *
 * Each case stores result in memory; no fixed golden (characterization test).
 * Results inspected post-simulation via waveform or ISS trace.
 */

#include <stdint.h>
#include <stdio.h>

/* Test result structure */
struct clipr_case {
    int32_t rs1;
    int32_t rs2;
    int32_t result_clipr;
    int32_t result_clipur;  /* for completeness */
};

/* Storage for all test cases */
#define NUM_CASES 28
static struct clipr_case test_results[NUM_CASES];

/* Encoding macros for COREV clipr/clipur instructions
 *
 * cv.clipr rd, rs1, rs2
 *   opcode=0x2B (bits 6:0)
 *   funct7=0x3A (bits 31:25) - clipr variant
 *   funct3=0x3  (bits 14:12)
 *   Format: .insn r rd, funct3, funct7, rs1, rs2
 *
 * cv.clipur rd, rs1, rs2
 *   opcode=0x2B
 *   funct7=0x3B (bits 31:25) - clipur variant
 *   funct3=0x3
 */

/* Inline assembly helper: execute cv.clipr rd, rs1, rs2
 * Returns result in rd (passed back via constraint).
 */
static int32_t cv_clipr(int32_t rs1, int32_t rs2) {
    int32_t rd;
    __asm__ volatile (
        ".insn r 0x2B, 0x3, 0x3A, %0, %1, %2\n\t"  /* cv.clipr rd, rs1, rs2 */
        : "=r"(rd)
        : "r"(rs1), "r"(rs2)
    );
    return rd;
}

/* Inline assembly helper: execute cv.clipur rd, rs1, rs2
 * Unsigned variant (clips to unsigned range).
 */
static int32_t cv_clipur(int32_t rs1, int32_t rs2) {
    int32_t rd;
    __asm__ volatile (
        ".insn r 0x2B, 0x3, 0x3B, %0, %1, %2\n\t"  /* cv.clipur rd, rs1, rs2 */
        : "=r"(rd)
        : "r"(rs1), "r"(rs2)
    );
    return rd;
}

/* Library clip logic reference (expected ISS behavior):
 *
 * For cv.clipr (signed clip):
 *   low  = ~rs2         (bitwise NOT)
 *   high = rs2
 *
 *   if (rs1 < low)  result = low
 *   else if (rs1 > high) result = high
 *   else result = rs1
 *
 * When rs2 is negative (e.g., 0x93130db0 = -1807695424 signed):
 *   low = ~0x93130db0 = 0x6cecf24f
 *   high = 0x93130db0 (negative, -1807695424 in signed)
 *
 *   For rs1=0x0000ffff (65535 signed):
 *     rs1 < low?  65535 < 0x6cecf24f (1837787727)? YES → result = low
 *
 * ISS expected: 0x6cecf24f
 * RTL observed: 0x0000ffff (passthrough / bypass?)
 *
 * For cv.clipur (unsigned clip):
 *   Clip to range [~rs2, rs2], unsigned comparison.
 */

int main(void) {
    int32_t idx = 0;

    /* Case 1: Reproduces co-sim divergence
     * rs2=0x93130db0 (negative), rs1=0x0000ffff
     * Expected ISS: low = 0x6cecf24f (rs1 < low)
     * Observed RTL: 0x0000ffff (passthrough)
     */
    test_results[idx].rs1 = 0x0000ffff;
    test_results[idx].rs2 = 0x93130db0;
    test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
    test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
    idx++;

    /* Case 2a: Minimum int32 as rs2
     * rs2=0x80000000 (-2147483648), rs1=0x00000000
     * low = ~0x80000000 = 0x7fffffff (2147483647)
     * high = 0x80000000 (negative)
     * Expected ISS: rs1 (0) < low (0x7fffffff)? YES → result = low
     */
    test_results[idx].rs1 = 0x00000000;
    test_results[idx].rs2 = 0x80000000;
    test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
    test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
    idx++;

    /* Case 2b: rs2=0x80000000, rs1=0x00000001 */
    test_results[idx].rs1 = 0x00000001;
    test_results[idx].rs2 = 0x80000000;
    test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
    test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
    idx++;

    /* Case 2c: rs2=0x80000000, rs1=0xffffffff (-1 signed) */
    test_results[idx].rs1 = 0xffffffff;
    test_results[idx].rs2 = 0x80000000;
    test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
    test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
    idx++;

    /* Case 3a: rs2=0xffffffff (-1), rs1=0x00000000
     * low = ~0xffffffff = 0x00000000
     * high = 0xffffffff (negative)
     * Expected ISS: rs1 (0) < low (0)? NO; rs1 > high? Depends on sign
     */
    test_results[idx].rs1 = 0x00000000;
    test_results[idx].rs2 = 0xffffffff;
    test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
    test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
    idx++;

    /* Case 3b: rs2=0xffffffff, rs1=0x00000005 */
    test_results[idx].rs1 = 0x00000005;
    test_results[idx].rs2 = 0xffffffff;
    test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
    test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
    idx++;

    /* Case 3c: rs2=0xffffffff, rs1=0xfffffffb (-5 signed) */
    test_results[idx].rs1 = 0xfffffffb;
    test_results[idx].rs2 = 0xffffffff;
    test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
    test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
    idx++;

    /* Case 4a: Degenerate zero bound: rs2=0x00000000
     * low = ~0x00000000 = 0xffffffff (-1)
     * high = 0x00000000
     * Range: [-1, 0] in signed
     * rs1=0xfffffffe (-2 signed)
     * Expected ISS: -2 < -1? YES → result = low = -1
     */
    test_results[idx].rs1 = 0xfffffffe;
    test_results[idx].rs2 = 0x00000000;
    test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
    test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
    idx++;

    /* Case 4b: rs2=0x00000000, rs1=0xffffffff (-1) */
    test_results[idx].rs1 = 0xffffffff;
    test_results[idx].rs2 = 0x00000000;
    test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
    test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
    idx++;

    /* Case 4c: rs2=0x00000000, rs1=0x00000000 */
    test_results[idx].rs1 = 0x00000000;
    test_results[idx].rs2 = 0x00000000;
    test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
    test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
    idx++;

    /* Case 4d: rs2=0x00000000, rs1=0x00000001 */
    test_results[idx].rs1 = 0x00000001;
    test_results[idx].rs2 = 0x00000000;
    test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
    test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
    idx++;

    /* Case 4e: rs2=0x00000000, rs1=0x00000002 */
    test_results[idx].rs1 = 0x00000002;
    test_results[idx].rs2 = 0x00000000;
    test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
    test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
    idx++;

    /* Case 5a: Control - normal positive bounds
     * rs2=0x0000000f (15), rs1=0xffffffff (-1 signed)
     * low = ~0x0000000f = 0xfffffff0 (-16 signed)
     * high = 0x0000000f (15)
     * Range: [-16, 15]
     * rs1 (-1) in range? -1 > -16 and -1 < 15? YES → result = rs1 = -1
     */
    test_results[idx].rs1 = 0xffffffff;
    test_results[idx].rs2 = 0x0000000f;
    test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
    test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
    idx++;

    /* Case 5b: rs2=0x0f, rs1=0x00000008 (inside range [-16, 15]) */
    test_results[idx].rs1 = 0x00000008;
    test_results[idx].rs2 = 0x0000000f;
    test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
    test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
    idx++;

    /* Case 5c: rs2=0x0f, rs1=0x00000010 (above high=15) */
    test_results[idx].rs1 = 0x00000010;
    test_results[idx].rs2 = 0x0000000f;
    test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
    test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
    idx++;

    /* Batch 2 (2026-07-21): pin down the rs2=INT_MIN anomaly.
     * Cases 14-20: rs2=0x80000000 (INT_MIN), sweep rs1 to see if the
     * rs1==1 -> 0 anomaly is a single point or a region.
     */
    {
        static const uint32_t rs1_sweep_intmin[] = {
            0x00000002, 0x00000005, 0x00007fff, 0x7ffffffe,
            0x7fffffff, 0xfffffffe, 0x80000000,
        };
        for (uint32_t k = 0; k < sizeof(rs1_sweep_intmin) / sizeof(rs1_sweep_intmin[0]); k++) {
            test_results[idx].rs1 = (int32_t)rs1_sweep_intmin[k];
            test_results[idx].rs2 = 0x80000000;
            test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
            test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
            idx++;
        }
    }

    /* Cases 21-24: rs2=0x80000001 (INT_MIN+1) - is the anomaly tied to the
     * negation-overflow of INT_MIN specifically, or more general? */
    {
        static const uint32_t rs1_sweep_intminp1[] = {
            0x00000000, 0x00000001, 0x00000002, 0xffffffff,
        };
        for (uint32_t k = 0; k < sizeof(rs1_sweep_intminp1) / sizeof(rs1_sweep_intminp1[0]); k++) {
            test_results[idx].rs1 = (int32_t)rs1_sweep_intminp1[k];
            test_results[idx].rs2 = 0x80000001;
            test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
            test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
            idx++;
        }
    }

    /* Cases 25-26: rs2=0xc0000000 - intermediate negative control point. */
    {
        static const uint32_t rs1_sweep_c0[] = {
            0x00000001, 0x40000000,
        };
        for (uint32_t k = 0; k < sizeof(rs1_sweep_c0) / sizeof(rs1_sweep_c0[0]); k++) {
            test_results[idx].rs1 = (int32_t)rs1_sweep_c0[k];
            test_results[idx].rs2 = 0xc0000000;
            test_results[idx].result_clipr = cv_clipr(test_results[idx].rs1, test_results[idx].rs2);
            test_results[idx].result_clipur = cv_clipur(test_results[idx].rs1, test_results[idx].rs2);
            idx++;
        }
    }

    /* Print all results in a greppable format for post-run inspection */
    for (idx = 0; idx < NUM_CASES; idx++) {
        printf("CLIPR_CASE %02d rs1=0x%08x rs2=0x%08x clipr=0x%08x clipur=0x%08x\n",
               idx,
               (uint32_t)test_results[idx].rs1,
               (uint32_t)test_results[idx].rs2,
               (uint32_t)test_results[idx].result_clipr,
               (uint32_t)test_results[idx].result_clipur);
    }

    return 0;
}
