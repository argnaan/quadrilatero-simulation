#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H

/* RISCOF target macros for GVSOC (cv32e40p-v2-standalone* targets).

   Differs from the RTL plugin (riscof/cv32e40p/env/model_test.h) in two
   places, both because GVSOC has no testbench to read the signature out of
   memory for us:

   - RVMODEL_BOOT emits a trampoline at BOOT_ADDR instead of storing the
     signature bounds into a testbench mailbox.
   - RVMODEL_HALT streams the signature to the virtual exit device before
     halting (see below).

   Signature extraction: the exit device at 0x20000000 implements the halt
   registers but its signature registers are stubs, so the test walks
   [begin_signature, end_signature) itself and stores every word to offset
   +0x80. That offset decodes to no register, and the device logs each write
   as "unknown offset 0x80 wdata=0x........" on its debug trace. The plugin
   runs GVSOC with --trace=/soc/exit --trace-level=debug and rebuilds the
   signature from those lines, in order.

   This is a workaround for the unimplemented SIG_START/SIG_END/SIG_WRITE
   registers in pulp/cv32e40p_exit/cv32e40p_exit_device_v2.cpp. Implementing
   them properly would let RVMODEL_HALT hand over the two bounds and have the
   device dump the region straight to a file, removing both the trace
   dependency and the per-word store loop. */

#define RVMODEL_EXIT_DEV_BASE 0x20000000
#define RVMODEL_SIG_SINK      0x20000080
#define RVMODEL_HALT_MAGIC    123456789

#define RVMODEL_DATA_SECTION \
        .pushsection .tohost,"aw",@progbits;                            \
        .align 8; .global tohost; tohost: .dword 0;                     \
        .align 8; .global fromhost; fromhost: .dword 0;                 \
        .popsection;                                                    \
        .align 8; .global begin_regstate; begin_regstate:               \
        .word 128;                                                      \
        .align 8; .global end_regstate; end_regstate:                   \
        .word 4;

/* Stream the signature to the exit device, then write the halt magic to the
   status register, which stops the simulation. */
#define RVMODEL_HALT                                                    \
  la    t0, begin_signature;                                            \
  la    t1, end_signature;                                              \
  li    t2, RVMODEL_SIG_SINK;                                           \
1:                                                                      \
  bgeu  t0, t1, 2f;                                                     \
  lw    t3, 0(t0);                                                      \
  sw    t3, 0(t2);                                                      \
  addi  t0, t0, 4;                                                      \
  j     1b;                                                             \
2:                                                                      \
  li    t4, RVMODEL_EXIT_DEV_BASE;                                      \
  li    t5, RVMODEL_HALT_MAGIC;                                         \
  sw    t5, 0(t4);                                                      \
3:                                                                      \
  j     3b;

/* The core boots at the fixed BOOT_ADDR (0x80), not at the ELF entry, so
   jump from there to the test entry point. t0 is scratch: the test prologue
   initialises the register file before use.

   Deliberately no mtvec write here. arch_test.h runs RVTEST_TRAP_PROLOG,
   which installs the trap handler and sets mtvec, immediately BEFORE
   RVMODEL_BOOT; zeroing mtvec at this point discards that handler and every
   test that takes a trap then loops forever at address 0. */
#define RVMODEL_BOOT                                                    \
  .pushsection .text.boot,"ax",@progbits;                               \
  lui   t0, %hi(rvtest_entry_point);                                    \
  addi  t0, t0, %lo(rvtest_entry_point);                                \
  jr    t0;                                                             \
  .popsection;

//RV_COMPLIANCE_DATA_BEGIN
#define RVMODEL_DATA_BEGIN                                              \
  RVMODEL_DATA_SECTION                                                        \
  .align 4;\
  .global begin_signature; begin_signature:

//RV_COMPLIANCE_DATA_END
#define RVMODEL_DATA_END                                                      \
  .align 4;\
  .global end_signature; end_signature:

//RVTEST_IO_INIT
#define RVMODEL_IO_INIT
//RVTEST_IO_WRITE_STR
#define RVMODEL_IO_WRITE_STR(_R, _STR)
//RVTEST_IO_CHECK
#define RVMODEL_IO_CHECK()
//RVTEST_IO_ASSERT_GPR_EQ
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
//RVTEST_IO_ASSERT_SFPR_EQ
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
//RVTEST_IO_ASSERT_DFPR_EQ
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

#define RVMODEL_SET_MSW_INT

#define RVMODEL_CLEAR_MSW_INT

#define RVMODEL_CLEAR_MTIMER_INT

#define RVMODEL_CLEAR_MEXT_INT

#define SET_REL_TVAL_MSK 0x00000000
#define NUM_SPECD_EXCPTCAUSES 3
#define EXCPT_CAUSE_MSK 0x1F

#define RVMODEL_MTVEC_ALIGN 8

#endif // _COMPLIANCE_MODEL_H
