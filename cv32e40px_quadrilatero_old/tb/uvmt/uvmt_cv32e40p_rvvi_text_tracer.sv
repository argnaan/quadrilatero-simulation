// =============================================================================
// uvmt_cv32e40p_rvvi_text_tracer.sv
//
// RTL-only RVVI-TEXT trace generator.  Drives the rvviTrace interface
// from the DUT RVFI -- reusing the shared uvmt_cv32e40p_iss_wrap_common.svh
// wiring -- and emits dut.rvvi through the librvvi_text.so DPI shim.  NO GVSOC,
// NO ISS, NO step-n-compare: this is the DUT-only writer.
//
// Compiled under RVVI_TRACE, in two modes: RTL-only (no USE_ISS), where this
// module is the sole producer on the rvvi interface and emits dut.rvvi on its
// own; and dual-trace co-sim (USE_ISS also defined), where a co-sim wrap on
// the same rvvi_if drives it for step-n-compare and this module compiles its
// driving wiring out (`ifndef USE_ISS), reads the interface, and remains the
// sole dut.rvvi producer while the bridge writes ref.rvvi.
//
// The RVFI->RVVI macros are shared with uvmt_cv32e40p_gvsoc_wrap.sv via
// uvmt_cv32e40p_rvfi2rvvi_macros.svh.
// =============================================================================

`ifndef __UVMT_CV32E40P_RVVI_TEXT_TRACER_SV__
`define __UVMT_CV32E40P_RVVI_TEXT_TRACER_SV__

`include "uvmt_cv32e40p_rvfi2rvvi_macros.svh"
`include "uvmt_cv32e40p_csr_defs.svh"

module uvmt_cv32e40p_rvvi_text_tracer
  #(
     parameter int ILEN   = 32,
     parameter int XLEN   = 32,
     parameter int FPU    = 0,    // 0 -> FLEN 0 (no FPU), else FLEN 32
     parameter int ZFINX  = 0,    // accepted for API symmetry with the wraps
     parameter int NHART  = 1,
     parameter int RETIRE = 1
    )
    (
        // RTL-only: sole producer, drives the interface below.  Dual-trace:
        // read-only alongside the co-sim wrap (see header).  Which mode
        // applies is a compile-time fact (`ifdef USE_ISS below).
        rvviTrace  rvvi
    );

    // librvvi_text.so DPI shim (RTL-only writer; no GVSOC dependency).
    import "DPI-C" function int  rvviTextOpen(input string path,
                                              input int unsigned ilen,
                                              input int unsigned xlen,
                                              input int unsigned flen,
                                              input int unsigned vlen,
                                              input int unsigned nhart,
                                              input int unsigned retire);
    import "DPI-C" function void rvviTextSetGpr (input int unsigned idx,  input longint unsigned value);
    import "DPI-C" function void rvviTextSetFpr (input int unsigned idx,  input longint unsigned value);
    import "DPI-C" function void rvviTextSetCsr (input int unsigned addr, input longint unsigned value);
    import "DPI-C" function void rvviTextSetMode(input int unsigned mode);
    import "DPI-C" function void rvviTextWrite  (input longint unsigned pc,
                                                 input longint unsigned insn,
                                                 input byte unsigned    isTrap);
    import "DPI-C" function void rvviTextClose();

    localparam int FLEN = (FPU != 0) ? 32 : 0;

    // Register an RVVI client so interrupt/haltreq nets have a consumer here
    // too; we drain and discard them (no reference model). Needed in both
    // modes: net_push() broadcasts to every registered client's queue
    // (rvviTrace.sv), so in dual-trace the nets gvsoc_wrap pushes land in
    // this client's queue as well -- left undrained they'd grow unbounded.
    // This tracer never pushes its own nets in dual-trace (its driving
    // `include below compiles out), it only drains.
    int client_id;
    initial begin
        client_id = rvvi.client_register(1'b1, 1'b0);
    end

    // Open dut.rvvi (override path with +rvvi_text_dut=<path>) and write header.
    // A failed open must be loud: the writer silently drops every line after
    // it, and a passing run with no trace file is easy to miss in a batch.
    string dut_path = "dut.rvvi";
    initial begin
        void'($value$plusargs("rvvi_text_dut=%s", dut_path));
        if (!rvviTextOpen(dut_path, ILEN, XLEN, FLEN, 0, NHART, RETIRE))
            $error("[rvvi_text_tracer] cannot open '%s' - no dut.rvvi will be written", dut_path);
    end

    // Flush and close at end of simulation.
    final begin
        rvviTextClose();
    end

    // Common RVFI->RVVI wiring: drives rvvi.{valid,pc,insn,trap,mode,x_*,f_*,csr*}
    // from the DUT RVFI.  Same include the GVSOC/Imperas wraps use.  Compiled
    // in only when USE_ISS is NOT defined: in dual-trace the co-sim wrap on
    // this same rvvi_if already includes it, and a second copy would
    // double-drive every rvvi.csr[]/mode[] net the shared macros touch.
    // NOTE: must stay a plain `ifdef (not a generate-if guarding the
    // `include) -- the shared .svh has its own top-level generate region,
    // and SystemVerilog disallows nesting one generate scope inside another.
`ifndef USE_ISS
    `include "uvmt_cv32e40p_iss_wrap_common.svh"

    // The shared include gates mtval wiring behind `ifdef USE_GVSOC; the RTL-only
    // RVVI_TRACE path must drive it here, else trap lines emit mtval=0 (undriven).
    `RVVI_SET_TRAP_CSR(`CSR_MTVAL_ADDR, mtval)
`endif

    // A trap entry flushes the killed pipeline slot and RVFI reports it as one
    // bogus row: pc_rdata=0 with insn = the synthesized jump to the handler.
    // The artifact is recognized by state -- it is the row immediately following
    // a trap row -- not by value, so a genuine retire at address 0 (test
    // trampolines) is not confused with it and is still traced.
    logic post_trap_flush [NHART] = '{default: 1'b0};

    // Per-retire: extract the architectural write-set and emit one RVVI-TEXT line.
    // Mirrors the DUT-side push loop of rvvi_trace2api.sv, minus all rvviRef*/ISS
    // steps -- the line goes straight to the DUT-only writer.
    always @(posedge rvvi.clk) begin
        for (int h = 0; h < NHART; h++) begin
            for (int r = 0; r < RETIRE; r++) begin
                if (rvvi.valid[h][r]) begin
                    // Drop only the trap-redirect flush row (see post_trap_flush
                    // above); trap rows themselves always go through.
                    if (rvvi.trap[h][r] ||
                        !(post_trap_flush[h] && rvvi.pc_rdata[h][r] == 0)) begin

                        // GPR write-set (x0 hardwired zero -> skip).
                        for (int i = 1; i < 32; i++)
                            if (rvvi.x_wb[h][r][i])
                                rvviTextSetGpr(i, rvvi.x_wdata[h][r][i]);

                        // FPR write-set.
                        for (int i = 0; i < 32; i++)
                            if (rvvi.f_wb[h][r][i])
                                rvviTextSetFpr(i, rvvi.f_wdata[h][r][i]);

                        // CSR write-set (sparse scan over the 4096-bit wb vector).
                        begin
                            automatic int wb_total = $countones(rvvi.csr_wb[h][r]);
                            if (wb_total > 0) begin
                                automatic int wb_found = 0;
                                for (int i = 0; i < 4096 && wb_found < wb_total; i++)
                                    if (rvvi.csr_wb[h][r][i]) begin
                                        rvviTextSetCsr(i, rvvi.csr[h][r][i]);
                                        wb_found++;
                                    end
                            end
                        end

                        // Trap exception CSRs lag csr_wb by one delta cycle; push
                        // the combinatorially-stable rvvi.csr values explicitly
                        // (same as rvvi_trace2api.sv on the trap path).
                        if (rvvi.trap[h][r]) begin
                            rvviTextSetCsr(`CSR_MSTATUS_ADDR, rvvi.csr[h][r][`CSR_MSTATUS_ADDR]);
                            rvviTextSetCsr(`CSR_MEPC_ADDR,    rvvi.csr[h][r][`CSR_MEPC_ADDR]);
                            rvviTextSetCsr(`CSR_MCAUSE_ADDR,  rvvi.csr[h][r][`CSR_MCAUSE_ADDR]);
                            rvviTextSetCsr(`CSR_MTVAL_ADDR,   rvvi.csr[h][r][`CSR_MTVAL_ADDR]);
                        end

                        // Privilege MODE column -- free from the rvvi interface.
                        rvviTextSetMode(rvvi.mode[h][r]);

                        // Emit one line: TRAP for synchronous exceptions, else RET.
                        rvviTextWrite(rvvi.pc_rdata[h][r], rvvi.insn[h][r],
                                      rvvi.trap[h][r] ? 8'd1 : 8'd0);
                    end // architectural retire guard
                    else
                        $display("[rvvi_text_tracer] dropped trap-redirect flush row (insn=0x%08x)",
                                 rvvi.insn[h][r]);

                    // Arm the filter: the row after a trap row is the flush artifact.
                    post_trap_flush[h] = rvvi.trap[h][r];

                    // Drain (and discard) the interrupt/haltreq nets the common
                    // wiring pushed; without a reference model nobody else pops.
                    begin
                        string name;
                        longint unsigned value;
                        longint unsigned pslot;
                        while (rvvi.net_pop(client_id, name, value, pslot)) begin
                            // discard: no reference model consumes the nets here
                        end
                    end
                end
            end
        end
    end

endmodule : uvmt_cv32e40p_rvvi_text_tracer

`endif // __UVMT_CV32E40P_RVVI_TEXT_TRACER_SV__
