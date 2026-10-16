
/*
**
** Copyright 2020 OpenHW Group
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
*******************************************************************************
** Debugger code
*******************************************************************************
*/

.section .debugger, "ax"
.global _debugger_start
.set test_ret_val, 0x20000000

.set test_fail, 0x1
.set test_debugger_ok, 0xa5

.set max_boot_skid, 0x20

_debugger_start:
    // Check that debug was entered inside the boot sequence, NOT that dpc is
    // exactly the boot address.
    //
    // Why the exact check was wrong: this test raises debug_req_i 1..35 cycles
    // after reset deassertion (uvmt_cv32e40p_firmware_test.sv::bootset_debug),
    // a delay UNCORRELATED with the boot latency - which +fixed_instr_gnt_stall
    // and the FPU configs stretch. The core is conformant either way: it enters
    // debug on the instruction it is about to retire when the request rises, so
    // dpc scales with the boot latency. Same program, three configs, three
    // values: 0x80 (pulp), 0x84 (pulp_fpu), 0x88 (pulp_fpu_zfinx). Demanding
    // 0x80 made two of the three fail on a compliant DUT.
    //
    // Quantified: the first instruction retires at ~16 cycles, against a delay
    // drawn uniformly from [1:35], so the exact check fails on roughly 54% of
    // the seeds - a coin flip, independent of both DUT and ISS. Narrowing the
    // draw to [1:12] would restore the exact check just as well, and it is the
    // measurement-consistent bound; it was NOT chosen because it pays for the
    // fix by deleting the stimulus that made this test interesting (the debug
    // request landing at different points of the boot sequence). Widening the
    // ACCEPTANCE instead keeps the full [1:35] window and still fails on
    // anything that is not a boot-sequence entry.
    //
    // The bound is derived from the _start symbol (crt0.S), which the TB uses as
    // the boot address (uvme_cv32e40p_cfg.sv: boot_addr == 0x0000_0080), not
    // from a literal, so a relocated program keeps the check valid. Its size
    // stays inside the straight-line prologue: the first control transfer in
    // crt0 is the call to memset, ~0x34 bytes in, so no PC reached through a
    // branch or call can land inside the window - that is what keeps this check
    // meaningful rather than merely permissive. With +fixed_instr_gnt_stall=10
    // (present on every regress lane of this test) ~11 cycles per instruction
    // bound the skid to ~3 instructions; 8 instructions of window leave >2x
    // margin, and dropping that plusarg would surface here as a loud failure,
    // never as a silent pass.
    //
    // norelax around the la: _start sits 0x80 from __global_pointer$, so the
    // linker would otherwise relax the pc-relative pair into a gp-relative
    // addi - and gp is set BY the very instructions this check is timing, so it
    // is not yet valid at debug entry.
    csrr t1, dpc
.option push
.option norelax
    la t2, _start                  # boot_addr == &_start
.option pop
    bltu t1, t2, _debugger_error   # dpc below the boot address: real failure
    sub t1, t1, t2
    li t2, max_boot_skid
    bgeu t1, t2, _debugger_error   # too deep into the program: real failure

    // Write known value to memory@0x1000
    // We don't have any globals or pointers
    // at this time, so we must rely on
    // memory (hopefully) not being used
    la a0, test_debugger_entry
    li t0, test_debugger_ok
    sw t0, 0(a0)
    dret

_debugger_error:
    li a0, test_ret_val
    li t0, test_fail
    sw t0, 0(a0)
    dret

.section .data
.global test_debugger_entry
test_debugger_entry:
    .word 0
