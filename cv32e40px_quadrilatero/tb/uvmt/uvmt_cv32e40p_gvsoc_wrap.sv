
`ifndef __UVMT_CV32E40P_GVSOC_WRAP_SV__
`define __UVMT_CV32E40P_GVSOC_WRAP_SV__

// RVFI->RVVI macros (shared with uvmt_cv32e40p_rvvi_text_tracer.sv) and
// CSR address definitions.
`include "uvmt_cv32e40p_rvfi2rvvi_macros.svh"
`include "uvmt_cv32e40p_csr_defs.svh"

module uvmt_cv32e40p_gvsoc_wrap
  import uvm_pkg::*;
  import cv32e40px_pkg::*;
  import rvviApiPkg::*;
  #(
     // FPU gates the FP-CSR compare policy in ref_init and the RVVI-TEXT
     // header FLEN. ZFINX is declared for API symmetry with imperas_dv_wrap
     // (the FP-CSR policy is the same with or without it).
     parameter FPU   = 0,
     parameter ZFINX = 0
    )
    (
        rvviTrace  rvvi // RVVI SystemVerilog Interface
    );

    // Declared here so Questa resolves the DPI context within this module scope.
    import "DPI-C" function int rvviRefIsFinished();

    // Custom extension, not part of the vendored RVVI API: called from
    // ref_init below BEFORE rvviRefInit() so the bridge knows to skip opening
    // dut.rvvi (the SV tracer on this same rvvi_if is the sole dut.rvvi
    // producer when RVVI_TRACE is also compiled in).
    import "DPI-C" function void rvviBridgeSetRefOnly(input byte unsigned refOnly);

    // Custom extension: CFG-derived FLEN for the RVVI-TEXT PARAMS header.
    // Also called before rvviRefInit(); without it the bridge falls back to
    // FLEN 32 and its header diverges from the tracer's on no-FPU configs.
    import "DPI-C" function void rvviBridgeSetFlen(input int unsigned flen);

    // Instantiate Open-Source Sync Bridge. The RVFI data-memory view feeds
    // the bridge's volatile memory window sync (rvviRefMemorySetVolatile).
    rvvi_trace2api #(
        .NHART(1),
        .RETIRE(1)
    )
    gvsoc_sync(
        .rvvi          (rvvi),
        .dut_mem_addr  (`RVFI_IF.rvfi_mem_addr),
        .dut_mem_rmask (`RVFI_IF.rvfi_mem_rmask),
        // Tracer-fidelity sidecar (+rvvi_tracer_fidelity): raw rvfi_intr
        // bundle and rvfi_dbg entry cause from the core tracer. rvfi_intr
        // needs the tracer patch that drives it (undriven upstream);
        // rvfi_dbg has always been driven.
        .dut_intr      (`RVFI_IF.rvfi_intr),
        .dut_dbg       (`RVFI_IF.rvfi_dbg)
    );

    ////////////////////////////////////////////////////////////////////////////
    // ISS completion watchdog.
    //
    // When the ISS-side firmware reaches the exit device, rvviRefIsFinished()
    // turns true. Normally the DUT reaches its own end-of-test write to the
    // status virtual peripheral too, the firmware test drops its objection
    // (uvmt_cv32e40p_firmware_test.sv run_phase wait) and run_test() winds
    // down the phases: phase_ended(final) sets sim_finished and end_of_test
    // prints an honest verdict.
    //
    // If instead the DUT is parked in an unwakeable WFI (ISS over-ran it,
    // e.g. through the resync machinery), that write never comes and the run
    // would burn wall-clock until the test_cfg watchdog (100 ms sim). This
    // block reaps such runs: after the ISS finishes it grants the DUT a
    // grace window (+iss_finish_grace_ns, default 2 ms sim time) and then
    // forces $finish from a non-clocked context.
    //
    // HONESTY CONTRACT: the forced $finish never upgrades a verdict. When it
    // fires, sim_finished is still 0 and end_of_test reports FAILED-ABORTED.
    // A clean end is only ever produced by the normal UVM shutdown, which
    // checks tests_passed/tests_failed/exit_value in the final phase and
    // folds the bridge mismatch count into err_count. If the DUT status
    // flags are already set (tp/tf/evalid, mirrored into the config_db by
    // uvmt_cv32e40p_tb), this block never kills the run.
    ////////////////////////////////////////////////////////////////////////////
    longint unsigned iss_finish_grace_ns = 2_000_000; // +iss_finish_grace_ns=<ns>

    initial begin
        bit        dut_tp, dut_tf, dut_evalid;
        bit [31:0] dut_evalue;
        bit        iss_done_seen;
        longint    grace_left_ns;
        void'($value$plusargs("iss_finish_grace_ns=%d", iss_finish_grace_ns));
        #1000000; // 1 ms: allow UVM env init and ref_init to complete
        forever begin
            #100000; // 100 us poll interval
            if (rvviRefIsFinished()) begin
                void'(uvm_config_db#(bit)::get(null, "*", "tp",     dut_tp));
                void'(uvm_config_db#(bit)::get(null, "*", "tf",     dut_tf));
                void'(uvm_config_db#(bit)::get(null, "*", "evalid", dut_evalid));
                if (dut_tp || dut_tf || dut_evalid) begin
                    // DUT-side end-of-test reached: the normal UVM shutdown
                    // owns the verdict (PASS or honest FAIL). Park forever.
                    `uvm_info(info_tag, "ISS finished and DUT status flags set - normal UVM shutdown owns the verdict", UVM_NONE)
                    wait (0);
                end
                if (!iss_done_seen) begin
                    iss_done_seen = 1;
                    grace_left_ns = iss_finish_grace_ns;
                    `uvm_info(info_tag, $sformatf("ISS finished, DUT not done - granting %0d ns grace before reaping", grace_left_ns), UVM_NONE)
                end
                else if (grace_left_ns <= 0) begin
                    void'(uvm_config_db#(bit[31:0])::get(null, "*", "evalue", dut_evalue));
                    `uvm_info(info_tag, $sformatf(
                        "ISS finished but DUT never completed (tp=%0b tf=%0b evalid=%0b evalue=0x%08x) - forcing $finish to unblock WFI (counts as ABORTED)",
                        dut_tp, dut_tf, dut_evalid, dut_evalue), UVM_NONE)
                    $finish(0);
                end
                else begin
                    grace_left_ns -= 100000;
                end
            end
        end
    end

    string info_tag = "GVSOC_wrap";

    // Common RVFI->RVVI wiring (CSRs, GPRs, FPRs, debug, IRQs)
    `include "uvmt_cv32e40p_iss_wrap_common.svh"

    /////////////////////////////////////////////////////////////////////////////
    // REF control
    /////////////////////////////////////////////////////////////////////////////
    task ref_init;
        string test_program_elf;
        reg [31:0] hart_id;
        bit [63:0] mtvec_addr_i;

        if (!rvviVersionCheck(RVVI_API_VERSION)) begin
            `uvm_fatal(info_tag, $sformatf("Expecting RVVI API version %0d.", RVVI_API_VERSION))
        end

        if ($value$plusargs("elf_file=%s", test_program_elf)) begin
`ifdef RVVI_TRACE
            // Dual-trace: the SV tracer alongside this wrap is the sole
            // dut.rvvi producer -- tell the bridge to open ref.rvvi only.
            // Must run before rvviRefInit(), where the file-open decision
            // happens; sequential task order guarantees that.
            rvviBridgeSetRefOnly(8'd1);
`endif
            rvviBridgeSetFlen((FPU != 0) ? 32 : 0);
            `uvm_info(info_tag, $sformatf("Loading ELF: %0s", test_program_elf), UVM_NONE)
            if (!rvviRefInit(test_program_elf)) begin
                `uvm_fatal(info_tag, "rvviRefInit failed")
            end
        end else begin
            `uvm_fatal(info_tag, "No elf_file plusarg specified")
        end

        hart_id = 32'h0000_0000;

        // --- Volatile CSRs: hardware-updated, cannot be predicted per-retire ---
        // Cycle counters only: time-derived, unpredictable per-retire.
        // minstret/minstreth (and the instreth user-mode shadow 0xC82) are
        // NOT volatile: retired-instruction count is architecturally
        // predictable and the ISS models the RTL semantics (increment per
        // retired instruction, ebreak excluded, same-row write suppression,
        // mcountinhibit.IR gate) - the compare Imperas ran too. instret
        // (0xC02) stays volatile for parity with the Imperas wrap.
        void'(rvviRefCsrSetVolatile(hart_id, `CSR_CYCLE_ADDR));
        void'(rvviRefCsrSetVolatile(hart_id, `CSR_CYCLEH_ADDR));
        void'(rvviRefCsrSetVolatile(hart_id, `CSR_INSTRET_ADDR));
        void'(rvviRefCsrSetVolatile(hart_id, `CSR_MCYCLE_ADDR));
        void'(rvviRefCsrSetVolatile(hart_id, `CSR_MCYCLEH_ADDR));
        // mip reflects async interrupt state; cannot be predicted.
        void'(rvviRefCsrSetVolatile(hart_id, `CSR_MIP_ADDR));
        // HPM counters and events are not modeled by the ISS.
        for (int i = 0; i < 29; i++) begin
            void'(rvviRefCsrSetVolatile(hart_id, 32'hB03 + i));  // mhpmcounter3..31
            void'(rvviRefCsrSetVolatile(hart_id, 32'hB83 + i));  // mhpmcounterh3..31
            void'(rvviRefCsrSetVolatile(hart_id, 32'h323 + i));  // mhpmevent3..31
        end

        // --- Volatile memory: TB virtual-peripheral registers no functional
        // model can predict (random-number generator @ 0x15001000, cycle
        // counter @ 0x15001004). Same window the Imperas wrap declares; a
        // DUT load from here has its rd copied into the ISS instead of
        // compared (bridge volatile memory window sync).
        void'(rvviRefMemorySetVolatile('h15001000, 'h15001007));

        // --- Compared CSRs: modeled by the GVSOC engine ---
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_MISA_ADDR,          RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_MSTATUS_ADDR,       RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_MIE_ADDR,           RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_MTVEC_ADDR,         RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_MCOUNTINHIBIT_ADDR, RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_MSCRATCH_ADDR,      RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_MEPC_ADDR,          RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_MCAUSE_ADDR,        RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_MTVAL_ADDR,         RVVI_TRUE));
        // Debug CSRs. The scratchpads are written from debug-ROM code only,
        // which both sides execute in lockstep - Imperas compared them too.
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_DCSR_ADDR,          RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_DPC_ADDR,           RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_DSCRATCH0_ADDR,     RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_DSCRATCH1_ADDR,     RVVI_TRUE));
        // Retired-instruction counters (see the volatile-set note above).
        // The sync SV pushes their live value on every retire row, so the
        // sticky mirror tracks the RTL count between explicit CSR writes.
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_MINSTRET_ADDR,      RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_MINSTRETH_ADDR,     RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, 32'hC82,                 RVVI_TRUE));
        // Trigger and implementation-ID CSRs - ISS reset values match RTL.
        // mimpid is excluded: the RTL step-compare path does not check it.
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_TDATA1_ADDR,    RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_TINFO_ADDR,     RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_MVENDORID_ADDR, RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_MARCHID_ADDR,   RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_MHARTID_ADDR,   RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_TSELECT_ADDR,   RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_TDATA2_ADDR,    RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_TDATA3_ADDR,    RVVI_TRUE));
        // Hwloop CSRs (PULP builds). On non-PULP builds both sides hold the
        // reset value, so the compare never fires.
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_LPSTART0_ADDR, RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_LPEND0_ADDR,   RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_LPCOUNT0_ADDR, RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_LPSTART1_ADDR, RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_LPEND1_ADDR,   RVVI_TRUE));
        void'(rvviRefCsrCompareEnable(hart_id, `CSR_LPCOUNT1_ADDR, RVVI_TRUE));
        // FP status CSRs (FPU builds only). Full compare: frm, fflags and
        // fcsr uncut. The historical fflags/fcsr[4:0] hold covered flag
        // defects in the flexfloat layer; those are fixed and the model is
        // Sail-conformant on the F suite (RISCOF 342/342), so flag accrual
        // is compared exactly as the Imperas wrap did.
        if (FPU != 0) begin
            void'(rvviRefCsrCompareEnable(hart_id, `CSR_FRM_ADDR,    RVVI_TRUE));
            void'(rvviRefCsrCompareEnable(hart_id, `CSR_FFLAGS_ADDR, RVVI_TRUE));
            void'(rvviRefCsrCompareEnable(hart_id, `CSR_FCSR_ADDR,   RVVI_TRUE));
        end

        // --- Interrupt/debug nets ---
        // Asynchronous interrupt grouping (group 1) and debug halt request (group 4).
        rvviRefNetGroupSet(rvviRefNetIndexGet("MSWInterrupt"),        1);
        rvviRefNetGroupSet(rvviRefNetIndexGet("MTimerInterrupt"),     1);
        rvviRefNetGroupSet(rvviRefNetIndexGet("MExternalInterrupt"),  1);
        for (int i = 0; i < 16; i++)
            rvviRefNetGroupSet(rvviRefNetIndexGet($sformatf("LocalInterrupt%0d", i)), 1);
        rvviRefNetGroupSet(rvviRefNetIndexGet("haltreq"),             4);

        // CV32E40P reset value for mtvec is 0x1 (vectored, base=0x0).
        mtvec_addr_i = 64'h1;
        if ($value$plusargs("mtvec_addr=%0x", mtvec_addr_i)) begin
            `uvm_info(info_tag, $sformatf("mtvec set to 0x%08x (from plusarg)", mtvec_addr_i), UVM_NONE)
        end else begin
            `uvm_info(info_tag, $sformatf("mtvec set to 0x%08x (reset default)", mtvec_addr_i), UVM_NONE)
        end
        rvviRefCsrSet(hart_id, `CSR_MTVEC_ADDR, mtvec_addr_i);

        `uvm_info(info_tag, "GVSOC ref_init complete", UVM_NONE)
    endtask

endmodule

`endif
