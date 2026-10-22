// =============================================================================
// uvmt_cv32e40p_rvfi2rvvi_macros.svh
//
// RVFI -> RVVI wiring macros shared by uvmt_cv32e40p_gvsoc_wrap.sv and
// uvmt_cv32e40p_rvvi_text_tracer.sv (uvmt_cv32e40p_imperas_dv_wrap.sv keeps
// its own copy - the ImperasDV path is not touched by this file).
// Every definition is `ifndef-guarded so the two consumers coexist if both
// end up in one compilation unit.
// =============================================================================

`ifndef __UVMT_CV32E40P_RVFI2RVVI_MACROS_SVH__
`define __UVMT_CV32E40P_RVFI2RVVI_MACROS_SVH__

`ifndef DUT_PATH
`define DUT_PATH dut_wrap.cv32e40px_tb_wrapper_i
`endif
`ifndef RVFI_IF
// The core's RAW RVFI port bundle (cv32e40p_tb_wrapper.rvfi_i: NRET=1,
// flat 32-bit signals, rmask/wmask bit-per-BIT via be_to_mask). NOT the
// generic multi-retire uvma_rvfi interface also named rvfi_i in
// uvmt_cv32e40p_tb.sv, whose consumers slice with XLEN*n +: XLEN - no
// slicing is needed (or correct) here.
`define RVFI_IF  `DUT_PATH.rvfi_i
`endif
`ifndef STRINGIFY
`define STRINGIFY(x) `"x`"
`endif

////////////////////////////////////////////////////////////////////////////
// Assign the rvvi CSR values from RVFI - CSR = (wdata & wmask) | (rdata & ~wmask)
////////////////////////////////////////////////////////////////////////////
`ifndef RVVI_SET_CSR
`define RVVI_SET_CSR(CSR_ADDR, CSR_NAME) \
    bit csr_``CSR_NAME``_wb; \
    wire [31:0] csr_``CSR_NAME``_w; \
    wire [31:0] csr_``CSR_NAME``_r; \
    assign csr_``CSR_NAME``_w = `RVFI_IF.rvfi_csr_``CSR_NAME``_wdata &   `RVFI_IF.rvfi_csr_``CSR_NAME``_wmask; \
    assign csr_``CSR_NAME``_r = `RVFI_IF.rvfi_csr_``CSR_NAME``_rdata & ~(`RVFI_IF.rvfi_csr_``CSR_NAME``_wmask); \
    assign rvvi.csr[0][0][``CSR_ADDR]    = csr_``CSR_NAME``_w | csr_``CSR_NAME``_r; \
    assign rvvi.csr_wb[0][0][``CSR_ADDR] = csr_``CSR_NAME``_wb; \
    always @(rvvi.csr[0][0][``CSR_ADDR]) begin \
        csr_``CSR_NAME``_wb = 1; \
    end \
    always @(posedge rvvi.clk) begin \
        if (`RVFI_IF.rvfi_valid && csr_``CSR_NAME``_wb) begin \
            csr_``CSR_NAME``_wb <= 0; \
        end \
    end
`endif

////////////////////////////////////////////////////////////////////////////
// Assign RVVI CSR values for trap-written CSRs (mstatus, mepc, mcause, mtval).
//
// Hardware trap writes set wmask=0 in RVFI; the standard formula would then
// yield rdata (stale), not the new trap value. Use wdata directly when
// wmask==0; fall back to the standard (wdata & wmask) | (rdata & ~wmask)
// formula for explicit CSR-write instructions.
////////////////////////////////////////////////////////////////////////////
`ifndef RVVI_SET_TRAP_CSR
`define RVVI_SET_TRAP_CSR(CSR_ADDR, CSR_NAME) \
    bit csr_``CSR_NAME``_wb; \
    wire [31:0] csr_``CSR_NAME``_wdata_raw; \
    wire [31:0] csr_``CSR_NAME``_wmask_raw; \
    wire [31:0] csr_``CSR_NAME``_rdata_raw; \
    assign csr_``CSR_NAME``_wdata_raw = `RVFI_IF.rvfi_csr_``CSR_NAME``_wdata; \
    assign csr_``CSR_NAME``_wmask_raw = `RVFI_IF.rvfi_csr_``CSR_NAME``_wmask; \
    assign csr_``CSR_NAME``_rdata_raw = `RVFI_IF.rvfi_csr_``CSR_NAME``_rdata; \
    assign rvvi.csr[0][0][``CSR_ADDR]    = (csr_``CSR_NAME``_wmask_raw == 32'h0) \
        ? csr_``CSR_NAME``_wdata_raw \
        : (csr_``CSR_NAME``_wdata_raw & csr_``CSR_NAME``_wmask_raw) \
          | (csr_``CSR_NAME``_rdata_raw & ~csr_``CSR_NAME``_wmask_raw); \
    assign rvvi.csr_wb[0][0][``CSR_ADDR] = csr_``CSR_NAME``_wb; \
    always @(rvvi.csr[0][0][``CSR_ADDR]) begin \
        csr_``CSR_NAME``_wb = 1; \
    end \
    always @(posedge rvvi.clk) begin \
        if (`RVFI_IF.rvfi_valid && csr_``CSR_NAME``_wb) begin \
            csr_``CSR_NAME``_wb <= 0; \
        end \
    end
`endif

`ifndef RVVI_SET_CSR_VEC
`define RVVI_SET_CSR_VEC(CSR_ADDR, CSR_NAME, CSR_ID) \
    bit csr_``CSR_NAME````CSR_ID``_wb; \
    wire [31:0] csr_``CSR_NAME````CSR_ID``_w; \
    wire [31:0] csr_``CSR_NAME````CSR_ID``_r; \
    assign csr_``CSR_NAME````CSR_ID``_w = `RVFI_IF.rvfi_csr_``CSR_NAME``_wdata[``CSR_ID] &   `RVFI_IF.rvfi_csr_``CSR_NAME``_wmask[``CSR_ID]; \
    assign csr_``CSR_NAME````CSR_ID``_r = `RVFI_IF.rvfi_csr_``CSR_NAME``_rdata[``CSR_ID] & ~(`RVFI_IF.rvfi_csr_``CSR_NAME``_wmask[``CSR_ID]); \
    assign rvvi.csr[0][0][``CSR_ADDR]    = csr_``CSR_NAME````CSR_ID``_w | csr_``CSR_NAME````CSR_ID``_r; \
    assign rvvi.csr_wb[0][0][``CSR_ADDR] = csr_``CSR_NAME````CSR_ID``_wb; \
    always @(rvvi.csr[0][0][``CSR_ADDR]) begin \
        csr_``CSR_NAME````CSR_ID``_wb = 1; \
    end \
    always @(posedge rvvi.clk) begin \
        if (`RVFI_IF.rvfi_valid && csr_``CSR_NAME````CSR_ID``_wb) begin \
            csr_``CSR_NAME````CSR_ID``_wb <= 0; \
        end \
    end
`endif

////////////////////////////////////////////////////////////////////////////
// Assign the NET IRQ values from the core irq inputs
////////////////////////////////////////////////////////////////////////////
`ifndef RVVI_WRITE_IRQ
`define RVVI_WRITE_IRQ(IRQ_NAME, IRQ_IDX) \
    wire   irq_``IRQ_NAME; \
    assign irq_``IRQ_NAME = `DUT_PATH.irq_i[IRQ_IDX]; \
    always @(irq_``IRQ_NAME) begin \
        void'(rvvi.net_push(`STRINGIFY(``IRQ_NAME), irq_``IRQ_NAME)); \
    end
`endif

`endif // __UVMT_CV32E40P_RVFI2RVVI_MACROS_SVH__
