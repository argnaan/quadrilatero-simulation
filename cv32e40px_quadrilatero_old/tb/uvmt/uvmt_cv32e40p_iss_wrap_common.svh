`ifndef __UVMT_CV32E40P_ISS_WRAP_COMMON_SVH__
`define __UVMT_CV32E40P_ISS_WRAP_COMMON_SVH__

// Common RVFI-to-RVVI wiring shared by the GVSOC and Imperas ISS wraps.
// Kept verbatim with the original Imperas wrap; every GVSOC-specific divergence
// is isolated under `ifdef USE_GVSOC so the Imperas path stays unchanged.
//
// The including module must define: `DUT_PATH, `RVFI_IF, the RVVI helpers
// `RVVI_SET_CSR / `RVVI_SET_CSR_VEC / `RVVI_WRITE_IRQ,
// `include "uvmt_cv32e40p_csr_defs.svh", and the `rvviTrace rvvi` port.
//
// `RVVI_SET_TRAP_CSR: trap-aware CSR helper. On a trap-induced write the RTL
// sets wmask=0 and the value is in wdata. A wrap that defines this macro before
// the include (GVSOC) gets the wdata-direct path; a wrap that does not (Imperas)
// falls back to `RVVI_SET_CSR -> the mstatus/mepc/mcause lines below are
// identical to the original on the Imperas path.
`ifndef RVVI_SET_TRAP_CSR
`define RVVI_SET_TRAP_CSR(CSR_ADDR, CSR_NAME) `RVVI_SET_CSR(CSR_ADDR, CSR_NAME)
`endif

    ////////////////////////////////////////////////////////////////////////////
    // Adopted from:
    // ImperasDV/examples/openhwgroup_cv32e40x/systemverilog/cv32e40x_testbench.sv
    //
    // InstrunctionBusFault(48) is in fact a TRAP which is derived externally
    // This is strange as other program TRAPS are derived by the model, for now
    // We have to ensure we do not step the REF model for this TRAP as it will
    // Step too far. So instead we block it as being VALID, but pass on the
    // signals.
    // maybe we need a different way to communicate this to the model, for
    // instance the ability to register a callback on fetch, in order to assert
    // this signal.
    ////////////////////////////////////////////////////////////////////////////
    assign rvvi.clk            = `RVFI_IF.clk_i;
    assign rvvi.valid[0][0]    = `RVFI_IF.rvfi_valid;
    assign rvvi.order[0][0]    = `RVFI_IF.rvfi_order;
    assign rvvi.insn[0][0]     = `RVFI_IF.rvfi_insn;
    assign rvvi.trap[0][0]     = `RVFI_IF.rvfi_trap.trap;
    assign rvvi.intr[0][0]     = `RVFI_IF.rvfi_intr.intr;
    assign rvvi.mode[0][0]     = `RVFI_IF.rvfi_mode;
    // rvfi_dbg_mode is an ENTRY marker (1 only on the instruction that enters
    // debug mode, FSM in DBG_TAKEN_*), not the persistent in-debug state; the
    // bridge debug-entry hook triggers on its 0->1 edge.
    assign rvvi.debug_mode[0][0] = `RVFI_IF.rvfi_dbg_mode;
    assign rvvi.ixl[0][0]      = `RVFI_IF.rvfi_ixl;
    assign rvvi.pc_rdata[0][0] = `RVFI_IF.rvfi_pc_rdata;
    //  assign rvvi.pc_wdata[0][0] = `RVFI_IF.rvfi_pc_wdata;

    `RVVI_SET_TRAP_CSR( `CSR_MSTATUS_ADDR, mstatus )  // trap write: wmask=0 -> take wdata
    `RVVI_SET_CSR( `CSR_MISA_ADDR,          misa          )
    `RVVI_SET_CSR( `CSR_MIE_ADDR,           mie           )
    `RVVI_SET_CSR( `CSR_MTVEC_ADDR,         mtvec         )
    `RVVI_SET_CSR( `CSR_MCOUNTINHIBIT_ADDR, mcountinhibit )
    `RVVI_SET_CSR( `CSR_MSCRATCH_ADDR,      mscratch      )
    `RVVI_SET_TRAP_CSR( `CSR_MEPC_ADDR,   mepc   )  // trap write: wmask=0 -> take wdata
    `RVVI_SET_TRAP_CSR( `CSR_MCAUSE_ADDR, mcause )  // trap write: wmask=0 -> take wdata
`ifdef USE_GVSOC
    // GVSOC models mtval; on a trap the RTL sets wmask=0 so take wdata.
    `RVVI_SET_TRAP_CSR( `CSR_MTVAL_ADDR,  mtval  )
`else
    //  `RVVI_SET_CSR( `CSR_MTVAL_ADDR,         mtval         )
`endif
    `RVVI_SET_CSR( `CSR_MIP_ADDR,           mip           )
    // `RVVI_SET_CSR( `CSR_MCYCLE_ADDR,        mcycle        )
    `RVVI_SET_CSR( `CSR_MINSTRET_ADDR,      minstret      )
    //  `RVVI_SET_CSR( `CSR_MCYCLEH_ADDR,       mcycleh       )
    `RVVI_SET_CSR( `CSR_MINSTRETH_ADDR,     minstreth     )
    `RVVI_SET_CSR( `CSR_INSTRET_ADDR,      instret      )
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT3_ADDR, mhpmevent, 3)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT4_ADDR, mhpmevent, 4)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT5_ADDR, mhpmevent, 5)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT6_ADDR, mhpmevent, 6)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT7_ADDR, mhpmevent, 7)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT8_ADDR, mhpmevent, 8)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT9_ADDR, mhpmevent, 9)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT10_ADDR, mhpmevent, 10)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT11_ADDR, mhpmevent, 11)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT12_ADDR, mhpmevent, 12)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT13_ADDR, mhpmevent, 13)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT14_ADDR, mhpmevent, 14)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT15_ADDR, mhpmevent, 15)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT16_ADDR, mhpmevent, 16)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT17_ADDR, mhpmevent, 17)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT18_ADDR, mhpmevent, 18)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT19_ADDR, mhpmevent, 19)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT20_ADDR, mhpmevent, 20)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT21_ADDR, mhpmevent, 21)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT22_ADDR, mhpmevent, 22)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT23_ADDR, mhpmevent, 23)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT24_ADDR, mhpmevent, 24)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT25_ADDR, mhpmevent, 25)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT26_ADDR, mhpmevent, 26)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT27_ADDR, mhpmevent, 27)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT28_ADDR, mhpmevent, 28)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT29_ADDR, mhpmevent, 29)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT30_ADDR, mhpmevent, 30)
    `RVVI_SET_CSR_VEC( `CSR_MHPMEVENT31_ADDR, mhpmevent, 31)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER3_ADDR, mhpmcounter, 3)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER3H_ADDR, mhpmcounterh, 3)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER4_ADDR,  mhpmcounter,  4)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER4H_ADDR, mhpmcounterh, 4)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER5_ADDR,  mhpmcounter,  5)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER5H_ADDR, mhpmcounterh, 5)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER6_ADDR,  mhpmcounter,  6)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER6H_ADDR, mhpmcounterh, 6)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER7_ADDR,  mhpmcounter,  7)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER7H_ADDR, mhpmcounterh, 7)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER8_ADDR,  mhpmcounter,  8)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER8H_ADDR, mhpmcounterh, 8)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER9_ADDR,  mhpmcounter,  9)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER9H_ADDR, mhpmcounterh, 9)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER10_ADDR,  mhpmcounter,  10)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER10H_ADDR, mhpmcounterh, 10)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER11_ADDR,  mhpmcounter,  11)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER11H_ADDR, mhpmcounterh, 11)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER12_ADDR,  mhpmcounter,  12)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER12H_ADDR, mhpmcounterh, 12)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER13_ADDR,  mhpmcounter,  13)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER13H_ADDR, mhpmcounterh, 13)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER14_ADDR,  mhpmcounter,  14)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER14H_ADDR, mhpmcounterh, 14)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER15_ADDR,  mhpmcounter,  15)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER15H_ADDR, mhpmcounterh, 15)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER16_ADDR,  mhpmcounter,  16)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER16H_ADDR, mhpmcounterh, 16)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER17_ADDR,  mhpmcounter,  17)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER17H_ADDR, mhpmcounterh, 17)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER18_ADDR,  mhpmcounter,  18)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER18H_ADDR, mhpmcounterh, 18)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER19_ADDR,  mhpmcounter,  19)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER19H_ADDR, mhpmcounterh, 19)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER20_ADDR,  mhpmcounter,  20)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER20H_ADDR, mhpmcounterh, 20)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER21_ADDR,  mhpmcounter,  21)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER21H_ADDR, mhpmcounterh, 21)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER22_ADDR,  mhpmcounter,  22)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER22H_ADDR, mhpmcounterh, 22)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER23_ADDR,  mhpmcounter,  23)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER23H_ADDR, mhpmcounterh, 23)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER24_ADDR,  mhpmcounter,  24)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER24H_ADDR, mhpmcounterh, 24)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER25_ADDR,  mhpmcounter,  25)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER25H_ADDR, mhpmcounterh, 25)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER26_ADDR,  mhpmcounter,  26)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER26H_ADDR, mhpmcounterh, 26)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER27_ADDR,  mhpmcounter,  27)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER27H_ADDR, mhpmcounterh, 27)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER28_ADDR,  mhpmcounter,  28)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER28H_ADDR, mhpmcounterh, 28)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER29_ADDR,  mhpmcounter,  29)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER29H_ADDR, mhpmcounterh, 29)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER30_ADDR,  mhpmcounter,  30)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER30H_ADDR, mhpmcounterh, 30)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER31_ADDR,  mhpmcounter,  31)
    `RVVI_SET_CSR_VEC( `CSR_MHPMCOUNTER31H_ADDR, mhpmcounterh, 31)

    `RVVI_SET_CSR( `CSR_INSTRETH_ADDR,     instreth     )
    `RVVI_SET_CSR( `CSR_MVENDORID_ADDR,     mvendorid     )
    `RVVI_SET_CSR( `CSR_MARCHID_ADDR,       marchid       )
    //  `RVVI_SET_CSR( `CSR_MIMPID_ADDR,        mimpid        )
    `RVVI_SET_CSR( `CSR_MHARTID_ADDR,       mhartid       )

    //  `RVVI_SET_CSR( `CSR_TSELECT_ADDR,       tselect       )
    `RVVI_SET_CSR( `CSR_DCSR_ADDR,          dcsr          )
    `RVVI_SET_CSR( `CSR_DPC_ADDR,           dpc           )
    `RVVI_SET_CSR_VEC(`CSR_DSCRATCH0_ADDR, dscratch, 0)
    `RVVI_SET_CSR_VEC(`CSR_DSCRATCH1_ADDR, dscratch, 1)
    `RVVI_SET_CSR_VEC(`CSR_TDATA1_ADDR, tdata, 1)
    `RVVI_SET_CSR_VEC(`CSR_TDATA2_ADDR, tdata, 2)
    `RVVI_SET_CSR( `CSR_TINFO_ADDR,         tinfo         )


    `RVVI_SET_CSR(`CSR_FFLAGS_ADDR, fflags)
    `RVVI_SET_CSR(`CSR_FRM_ADDR   , frm   )
    `RVVI_SET_CSR(`CSR_FCSR_ADDR  , fcsr  )

    `RVVI_SET_CSR(`CSR_LPCOUNT0_ADDR  , lpcount0  )
    `RVVI_SET_CSR(`CSR_LPSTART0_ADDR  , lpstart0  )
    `RVVI_SET_CSR(`CSR_LPEND0_ADDR    , lpend0    )

    `RVVI_SET_CSR(`CSR_LPCOUNT1_ADDR  , lpcount1  )
    `RVVI_SET_CSR(`CSR_LPSTART1_ADDR  , lpstart1  )
    `RVVI_SET_CSR(`CSR_LPEND1_ADDR    , lpend1    )
    ////////////////////////////////////////////////////////////////////////////
    // Assign the RVVI GPR registers
    ////////////////////////////////////////////////////////////////////////////
    bit [31:0] XREG[32];
    genvar gi;
    generate
        for(gi=0; gi<32; gi++) begin
            assign rvvi.x_wdata[0][0][gi] = XREG[gi];
        end
    endgenerate

    always @(*) begin
        int i;
        for (i=1; i<32; i++) begin
            XREG[i] = 32'b0;
            // TODO: This current RVFI implementation will only allow a single destination
            //       register to be written. For some instructions this is not sufficient
            //       This code will need enhancing once the RVFI has the ability to describe
            //       multiple target register writes, for a single instruction
            if (`RVFI_IF.rvfi_rd_addr[0]==5'(i))
            XREG[i] = `RVFI_IF.rvfi_rd_wdata[0];
            if (`RVFI_IF.rvfi_rd_addr[1]==5'(i))
            XREG[i] = `RVFI_IF.rvfi_rd_wdata[1];
        end
    end

    assign rvvi.x_wb[0][0] = (1 << `RVFI_IF.rvfi_rd_addr[0] | 1 << `RVFI_IF.rvfi_rd_addr[1]); // TODO: originally rvfi_rd_addr

    ////////////////////////////////////////////////////////////////////////////
    // Assign the RVVI F GPR registers
    ////////////////////////////////////////////////////////////////////////////
    bit [31:0] FREG[32];

    bit is_f_reg [1:0];

    assign is_f_reg[0] = `RVFI_IF.rvfi_frd_wvalid[0];
    assign is_f_reg[1] = `RVFI_IF.rvfi_frd_wvalid[1];

    int f_reg_addr [1:0];
    assign f_reg_addr[0] = `RVFI_IF.rvfi_frd_addr[0];
    assign f_reg_addr[1] = `RVFI_IF.rvfi_frd_addr[1];

    genvar fgi;
    generate
        for(fgi=0; fgi<32; fgi++) begin
            assign rvvi.f_wdata[0][0][fgi] = FREG[fgi];
        end
    endgenerate

    always @(*) begin
        int i;
        for (i=0; i<32; i++) begin
            FREG[i] = 32'b0;
            if (is_f_reg[0] & (`RVFI_IF.rvfi_frd_addr[0]==5'(i)))
            FREG[i] = `RVFI_IF.rvfi_frd_wdata[0];
            if (is_f_reg[1] & (`RVFI_IF.rvfi_frd_addr[1]==5'(i)))
            FREG[i] = `RVFI_IF.rvfi_frd_wdata[1];
        end
    end

    assign rvvi.f_wb[0][0] = (is_f_reg[0] << f_reg_addr[0] | is_f_reg[1] << f_reg_addr[1]);

    ////////////////////////////////////////////////////////////////////////////
    // DEBUG REQUESTS,
    ////////////////////////////////////////////////////////////////////////////
    logic debug_req_i;
    assign debug_req_i = `DUT_PATH.debug_req_i;
    always @(debug_req_i) begin
        void'(rvvi.net_push("haltreq", debug_req_i));
    end

    ////////////////////////////////////////////////////////////////////////////
    // INTERRUPTS
    // assert when MIP or cause bit
    // negate when posedge clk && valid=1 && debug=0
    ////////////////////////////////////////////////////////////////////////////
    `RVVI_WRITE_IRQ(MSWInterrupt,        3)
    `RVVI_WRITE_IRQ(MTimerInterrupt,     7)
    `RVVI_WRITE_IRQ(MExternalInterrupt, 11)
    `RVVI_WRITE_IRQ(LocalInterrupt0,    16)
    `RVVI_WRITE_IRQ(LocalInterrupt1,    17)
    `RVVI_WRITE_IRQ(LocalInterrupt2,    18)
    `RVVI_WRITE_IRQ(LocalInterrupt3,    19)
    `RVVI_WRITE_IRQ(LocalInterrupt4,    20)
    `RVVI_WRITE_IRQ(LocalInterrupt5,    21)
    `RVVI_WRITE_IRQ(LocalInterrupt6,    22)
    `RVVI_WRITE_IRQ(LocalInterrupt7,    23)
    `RVVI_WRITE_IRQ(LocalInterrupt8,    24)
    `RVVI_WRITE_IRQ(LocalInterrupt9,    25)
    `RVVI_WRITE_IRQ(LocalInterrupt10,   26)
    `RVVI_WRITE_IRQ(LocalInterrupt11,   27)
    `RVVI_WRITE_IRQ(LocalInterrupt12,   28)
    `RVVI_WRITE_IRQ(LocalInterrupt13,   29)
    `RVVI_WRITE_IRQ(LocalInterrupt14,   30)
    `RVVI_WRITE_IRQ(LocalInterrupt15,   31)
`endif // __UVMT_CV32E40P_ISS_WRAP_COMMON_SVH__
