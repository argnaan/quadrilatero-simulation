//
// Copyright 2022 OpenHW Group
// Copyright 2022 Imperas
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://solderpad.org/licenses/
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//


`ifndef __UVMT_CV32E40P_IMPERAS_DV_WRAP_SV__
`define __UVMT_CV32E40P_IMPERAS_DV_WRAP_SV__

`define DUT_PATH dut_wrap.cv32e40px_tb_wrapper_i
`define RVFI_IF  `DUT_PATH.rvfi_i

`define STRINGIFY(x) `"x`"

////////////////////////////////////////////////////////////////////////////
// Assign the rvvi CSR values from RVFI - CSR = (wdata & wmask) | (rdata & ~wmask)
////////////////////////////////////////////////////////////////////////////
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

////////////////////////////////////////////////////////////////////////////
// Assign the NET IRQ values from the core irq inputs
////////////////////////////////////////////////////////////////////////////
`define RVVI_WRITE_IRQ(IRQ_NAME, IRQ_IDX) \
    wire   irq_``IRQ_NAME; \
    assign irq_``IRQ_NAME = `DUT_PATH.irq_i[IRQ_IDX]; \
    always @(irq_``IRQ_NAME) begin \
        void'(rvvi.net_push(`STRINGIFY(``IRQ_NAME), irq_``IRQ_NAME)); \
    end

////////////////////////////////////////////////////////////////////////////
// CSR definitions
////////////////////////////////////////////////////////////////////////////
`include "uvmt_cv32e40p_csr_defs.svh"

///////////////////////////////////////////////////////////////////////////////
// Module wrapper for Imperas DV.
////////////////////////////////////////////////////////////////////////////
// `define USE_ISS
`ifdef USE_ISS

`include "idv/idv.svh" // located in $IMPERAS_HOME/ImpProprietary/include/host

module uvmt_cv32e40p_imperas_dv_wrap
  import uvm_pkg::*;
  import cv32e40p_pkg::*;
//   import uvme_cv32e40p_pkg::*;
//   import uvmt_cv32e40p_pkg::*;
  import idvPkg::*;
  import rvviApiPkg::*;
  #(
     parameter FPU   = 0,
     parameter ZFINX = 0,
     parameter SET_IDV_RECONVERGE = 0
    )

    (
        rvviTrace  rvvi // RVVI SystemVerilog Interface
    );

    trace2log       idv_trace2log(rvvi);

    localparam bit F_REG = FPU & !ZFINX;

    trace2api #(
        .CMP_PC                 (1),
        .CMP_INS                (1),
        .CMP_GPR                (1),
        .CMP_FPR                (F_REG),
        .CMP_VR                 (0),
        .CMP_CSR                (1),
        .ON_MISMATCH_RECONVERGE (SET_IDV_RECONVERGE)
    )
    trace2api(rvvi);

    trace2cov       idv_trace2cov(rvvi);

    string info_tag = "ImperasDV_wrap";

    // Common RVFI->RVVI wiring (CSRs, GPRs, FPRs, debug, IRQs)
    `include "uvmt_cv32e40p_iss_wrap_common.svh"

    /////////////////////////////////////////////////////////////////////////////
    // REF control
    /////////////////////////////////////////////////////////////////////////////
    task ref_init;
    string test_program_elf;
    reg [31:0] hart_id;
    bit [64:0] mtvec_addr_i;

    // Select processor name
    void'(rvviRefConfigSetString(IDV_CONFIG_MODEL_NAME, "CV32E40P"));
    // Worst case propagation of events 19+2 retirements. (19 due to long fpu multicycle instr that observed meantime. +2 is buffer)
    void'(rvviRefConfigSetInt(IDV_CONFIG_MAX_NET_LATENCY_RETIREMENTS, 25));
    // Redirect stdout to parent systemverilog simulator
    void'(rvviRefConfigSetInt(IDV_CONFIG_REDIRECT_STDOUT, RVVI_TRUE));

    // Initialize REF and load the test-program into it's memory (do this before initializing the DUT).
    // TODO: is this the best place for this?
    if (!rvviVersionCheck(RVVI_API_VERSION)) begin
        `uvm_fatal(info_tag, $sformatf("Expecting RVVI API version %0d.", RVVI_API_VERSION))
    end
    // Test-program must have been compiled before we got here...
    if ($value$plusargs("elf_file=%s", test_program_elf)) begin
        `uvm_info(info_tag, $sformatf("ImperasDV loading test_program %0s", test_program_elf), UVM_NONE)
        void'(rvviRefConfigSetString(IDV_CONFIG_MODEL_VENDOR,  "openhwgroup.ovpworld.org"));
        void'(rvviRefConfigSetString(IDV_CONFIG_MODEL_NAME,    "CVE4P"));
        void'(rvviRefConfigSetString(IDV_CONFIG_MODEL_VARIANT, "CV32E40P"));
        if (!rvviRefInit(test_program_elf)) begin
            `uvm_fatal(info_tag, "rvviRefInit failed")
        end
        else begin
            `uvm_info(info_tag, "rvviRefInit() succeed", UVM_NONE)
        end
    end
    else begin
        `uvm_fatal(info_tag, "No test_program specified")
    end

    hart_id = 32'h0000_0000;

    void'(rvviRefCsrSetVolatile(hart_id, `CSR_CYCLE_ADDR        ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_CYCLEH_ADDR        ));

    void'(rvviRefCsrSetVolatile(hart_id, `CSR_INSTRET_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER3_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER3H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER4_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER4H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER5_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER5H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER6_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER6H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER7_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER7H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER8_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER8H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER9_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER9H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER10_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER10H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER11_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER11H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER12_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER12H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER13_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER13H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER14_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER14H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER15_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER15H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER16_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER16H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER17_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER17H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER18_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER18H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER19_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER19H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER20_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER20H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER21_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER21H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER22_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER22H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER23_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER23H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER24_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER24H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER25_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER25H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER26_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER26H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER27_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER27H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER28_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER28H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER29_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER29H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER30_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER30H_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER31_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMCOUNTER31H_ADDR      ));


    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT3_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT4_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT5_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT6_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT7_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT8_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT9_ADDR      ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT10_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT11_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT12_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT13_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT14_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT15_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT16_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT17_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT18_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT19_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT20_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT21_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT22_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT23_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT24_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT25_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT26_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT27_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT28_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT29_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT30_ADDR     ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MHPMEVENT31_ADDR     ));


    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MCYCLE_ADDR       ));
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MCYCLEH_ADDR       ));

    // cannot predict this register due to latency between
    // pending and taken
    void'(rvviRefCsrSetVolatile(hart_id, `CSR_MIP_ADDR          ));
    void'(rvviRefCsrSetVolatileMask(hart_id, `CSR_DCSR_ADDR, 'h8));

    // TODO silabs-hfegran: temp fix to work around issues
    // rvviRefCsrCompareEnable(hart_id, `CSR_DCSR_ADDR,   RVVI_FALSE);
    // end TODO
    // define asynchronous grouping
    // Interrupts
    rvviRefNetGroupSet(rvviRefNetIndexGet("MSWInterrupt"),        1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("MTimerInterrupt"),     1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("MExternalInterrupt"),  1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt0"),     1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt1"),     1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt2"),     1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt3"),     1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt4"),     1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt5"),     1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt6"),     1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt7"),     1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt8"),     1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt9"),     1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt10"),    1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt11"),    1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt12"),    1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt13"),    1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt14"),    1);
    rvviRefNetGroupSet(rvviRefNetIndexGet("LocalInterrupt15"),    1);

//  rvviRefNetGroupSet(rvviRefNetIndexGet("InstructionBusFault"), 2);

    // Debug
    rvviRefNetGroupSet(rvviRefNetIndexGet("haltreq"),             4);

    // MTVEC CSR initialization based on TB configuration
    if ($value$plusargs("mtvec_addr=%0x", mtvec_addr_i)) begin
      rvviRefCsrSet(hart_id, `CSR_MTVEC_ADDR, mtvec_addr_i);
    end

    void'(rvviRefMemorySetVolatile('h15001000, 'h15001007)); //TODO: deal with int return value
  endtask // ref_init
endmodule : uvmt_cv32e40p_imperas_dv_wrap
`endif  // USE_ISS

`endif // __UVMT_CV32E40P_IMPERAS_DV_WRAP_SV__
