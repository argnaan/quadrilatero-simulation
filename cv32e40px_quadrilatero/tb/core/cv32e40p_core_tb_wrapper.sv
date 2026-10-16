// Copyright 2018 Robert Balas <balasr@student.ethz.ch>
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Wrapper for a CV32E40P testbench, containing CV32E40P, Memory and stdout peripheral
// Contributor: Robert Balas <balasr@student.ethz.ch>
// Module renamed from riscv_wrapper to cv32e40p_tb_wrapper because (1) the
// name of the core changed, and (2) the design has a cv32e40p_wrapper module.
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-0.51

module cv32e40p_core_tb_wrapper
  import cv32e40px_core_v_xif_pkg::*;
  import obi_pkg::*;
    #(parameter // Parameters used by TB
                INSTR_RDATA_WIDTH = 32,
                RAM_ADDR_WIDTH    = 20,
                BOOT_ADDR         = 'h80,
                DM_HALTADDRESS    = 32'h1A11_0800,
                HART_ID           = 32'h0000_0000,
                // Parameters used by DUT
                COREV_PULP        = 0,
                COREV_CLUSTER     = 0,
                FPU               = 0,
                ZFINX             = 0,
                NUM_MHPMCOUNTERS  = 1
    )
    (
     input logic         clk_i,
     input logic         rst_ni,

     input logic         fetch_enable_i,
     output logic        tests_passed_o,
     output logic        tests_failed_o,
     output logic [31:0] exit_value_o,
     output logic        exit_valid_o
    );

    // signals connecting core 
    logic                         instr_req;
    logic                         instr_gnt;
    logic                         instr_rvalid;
    logic [31:0]                  instr_addr;
    logic [INSTR_RDATA_WIDTH-1:0] instr_rdata;

    logic                         core_data_req;
    logic                         core_data_gnt;
    logic                         core_data_rvalid;
    logic [31:0]                  core_data_addr;
    logic                         core_data_we;
    logic [3:0]                   core_data_be;
    logic [31:0]                  core_data_rdata;
    logic [31:0]                  core_data_wdata;

    // signals to memory
    logic                        mem_req;
    logic                        mem_gnt;
    logic                        mem_rvalid;
    logic [31:0]                 mem_addr;
    logic                        mem_we;
    logic [3:0]                  mem_be;
    logic [31:0]                 mem_rdata;
    logic [31:0]                 mem_wdata;

    // signals to debug unit
    logic                         debug_req;

    // irq signals (not used)
    logic [0:31]                  irq;
    logic [0:4]                   irq_id_in;
    logic                         irq_ack;
    logic [0:4]                   irq_id_out;
    logic                         irq_sec;

    // CORE-V-XIF signals
    // Compressed interface
    logic                         x_compressed_valid;
    logic                         x_compressed_ready;
    x_compressed_req_t            x_compressed_req;
    x_compressed_resp_t           x_compressed_resp;
    // Issue interface
    logic                         x_issue_valid;
    logic                         x_issue_ready;
    x_issue_req_t                 x_issue_req;
    x_issue_resp_t                x_issue_resp;
    // Commit interface
    logic                         x_commit_valid;
    x_commit_t                    x_commit;
    // Memory request/response interface
    logic                         x_mem_valid;
    logic                         x_mem_ready;
    x_mem_req_t                   x_mem_req;
    x_mem_resp_t                  x_mem_resp;
    // Memory Result Interface
    logic                         x_mem_result_valid;
    x_mem_result_t                x_mem_result;
    // Result Interface
    logic                         x_result_valid;
    logic                         x_result_ready;
    x_result_t                    x_result;



    // Quadrilatero to bridge interface
    logic                                         q_mem_req, q_mem_we, q_mem_gnt, q_mem_rvalid;
    logic [quadrilatero_pkg::BUS_WIDTH/8-1:0]     q_mem_be;
    logic [31:0]                                  q_mem_addr;
    logic [quadrilatero_pkg::BUS_WIDTH-1:0]       q_mem_wdata, q_mem_rdata;

    // Quadrilatero obi channels
    obi_req_t  quad_req  [4];
    obi_resp_t quad_resp [4];

    // interrupts (only timer for now)
    assign irq_sec     = '0;

//    // core log reports parameter usage and illegal instructions to the logfile
//    // MIKET: commenting out as the cv32e40p RTL wrapper does this as well.
//    cv32e40p_core_log
//     #(
//          .COREV_PULP            ( COREV_PULP            ),
//          .COREV_CLUSTER         ( COREV_CLUSTER         ),
//          .FPU                   ( FPU                   ),
//          .ZFINX                 ( ZFINX                 ),
//          .NUM_MHPMCOUNTERS      ( NUM_MHPMCOUNTERS      ))
//    core_log_i(
//          .clk_i              ( cv32e40p_core_i.id_stage_i.clk              ),
//          .is_decoding_i      ( cv32e40p_core_i.id_stage_i.is_decoding_o    ),
//          .illegal_insn_dec_i ( cv32e40p_core_i.id_stage_i.illegal_insn_dec ),
//          .hart_id_i          ( cv32e40p_core_i.hart_id_i                   ),
//          .pc_id_i            ( cv32e40p_core_i.pc_id                       )
//      );

    // instantiate the core
    cv32e40px_core #(
                 .COREV_X_IF       (1),
                 .COREV_PULP       (COREV_PULP),
                 .COREV_CLUSTER    (COREV_CLUSTER),
                 .FPU              (FPU),
                 .ZFINX            (ZFINX),
                 .NUM_MHPMCOUNTERS (NUM_MHPMCOUNTERS)
                )
    cv32e40px_core_i
        (
         .clk_i                  ( clk_i                 ),
         .rst_ni                 ( rst_ni                ),

         .pulp_clock_en_i        ( '1                    ),
         .scan_cg_en_i           ( '0                    ),

         .boot_addr_i            ( BOOT_ADDR             ),
         .dm_halt_addr_i         ( DM_HALTADDRESS        ),
         .hart_id_i              ( HART_ID               ),

         .instr_req_o            ( instr_req             ),
         .instr_gnt_i            ( instr_gnt             ),
         .instr_rvalid_i         ( instr_rvalid          ),
         .instr_addr_o           ( instr_addr            ),
         .instr_rdata_i          ( instr_rdata           ),

         .data_req_o             ( core_data_req         ),
         .data_gnt_i             ( core_data_gnt         ),
         .data_rvalid_i          ( core_data_rvalid      ),
         .data_we_o              ( core_data_we          ),
         .data_be_o              ( core_data_be          ),
         .data_addr_o            ( core_data_addr        ),
         .data_wdata_o           ( core_data_wdata       ),
         .data_rdata_i           ( core_data_rdata       ),

         .apu_req_o              (                       ),
         .apu_gnt_i              ( 1'b0                  ),
         .apu_operands_o         (                       ),
         .apu_op_o               (                       ),
         .apu_flags_o            (                       ),
         .apu_rvalid_i           ( 1'b0                  ),
         .apu_result_i           ( {32{1'b0}}            ),
         .apu_flags_i            ( {5{1'b0}}             ), // APU_NUSFLAGS_CPU

         // Interrupts verified in UVM environment
         .irq_i                  ( {32{1'b0}}            ),
         .irq_ack_o              ( irq_ack               ),
         .irq_id_o               ( irq_id_out            ),

         .debug_req_i            ( debug_req             ),

         .fetch_enable_i         ( fetch_enable_i        ),
         .core_sleep_o           ( core_sleep_o          ),

         // CORE-V-XIF
         // Compressed interface
        .x_compressed_valid_o  ( x_compressed_valid ),
        .x_compressed_ready_i  ( x_compressed_ready ),
        .x_compressed_req_o    ( x_compressed_req  ),
        .x_compressed_resp_i   ( x_compressed_resp ),

        // Issue interface
        .x_issue_valid_o       ( x_issue_valid      ),
        .x_issue_ready_i       ( x_issue_ready      ),
        .x_issue_req_o         ( x_issue_req        ),
        .x_issue_resp_i        ( x_issue_resp       ),

        // Commit interface
        .x_commit_valid_o      ( x_commit_valid     ),
        .x_commit_o            ( x_commit           ),

        // Memory request/response interface
        .x_mem_valid_i         ( x_mem_valid        ),
        .x_mem_ready_o         ( x_mem_ready        ),
        .x_mem_req_i           ( x_mem_req          ),
        .x_mem_resp_o          ( x_mem_resp         ),

        // Memory Result Interface
        .x_mem_result_valid_o  ( x_mem_result_valid ),
        .x_mem_result_o        ( x_mem_result       ),

        // Result Interface
        .x_result_valid_i      ( x_result_valid     ),
        .x_result_ready_o      ( x_result_ready     ),
        .x_result_i            ( x_result           )

       );

    // this handles read to RAM and memory mapped pseudo peripherals
    mm_ram
        #(.RAM_ADDR_WIDTH (RAM_ADDR_WIDTH),
          .INSTR_RDATA_WIDTH (INSTR_RDATA_WIDTH))
    ram_i
        (.clk_i          ( clk_i                                     ),
         .rst_ni         ( rst_ni                                    ),
         .dm_halt_addr_i ( DM_HALTADDRESS                            ),

         .instr_req_i    ( instr_req                                 ),
         .instr_addr_i   ( { {10{1'b0}},
                             instr_addr[RAM_ADDR_WIDTH-1:0]
                           }                                         ),
         .instr_rdata_o  ( instr_rdata                               ),
         .instr_rvalid_o ( instr_rvalid                              ),
         .instr_gnt_o    ( instr_gnt                                 ),

         .data_req_i     ( mem_req                                  ),
         .data_addr_i    ( mem_addr                                 ),
         .data_we_i      ( mem_we                                   ),
         .data_be_i      ( mem_be                                   ),
         .data_wdata_i   ( mem_wdata                                ),
         .data_rdata_o   ( mem_rdata                                ),
         .data_rvalid_o  ( mem_rvalid                               ),
         .data_gnt_o     ( mem_gnt                                  ),

         .irq_id_i       ( irq_id_out                                ),
         .irq_ack_i      ( irq_ack                                   ),
         .irq_o          ( irq                                       ),

         .debug_req_o    ( debug_req                                 ),

         .pc_core_id_i   ( cv32e40px_core_i.pc_id                    ),

         .tests_passed_o ( tests_passed_o                            ),
         .tests_failed_o ( tests_failed_o                            ),
         .exit_valid_o   ( exit_valid_o                              ),
         .exit_value_o   ( exit_value_o                              ));

    

    // Quadrilatero
    quadrilatero quad_i
    (
        .clk_i          ( clk_i ),
        .rst_ni         ( rst_ni ),

        // memory interface
        .mem_req_o              ( q_mem_req     ), 
        .mem_we_o               ( q_mem_we      ), 
        .mem_be_o               ( q_mem_be      ),
        .mem_addr_o             ( q_mem_addr    ), 
        .mem_wdata_o            ( q_mem_wdata   ),
        .mem_gnt_i              ( q_mem_gnt     ), 
        .mem_rvalid_i           ( q_mem_rvalid  ), 
        .mem_rdata_i            ( q_mem_rdata   ),
        
        // XIF interface
        // compressed interface
        .x_compressed_valid_i   ( x_compressed_valid ),
        .x_compressed_ready_o   ( x_compressed_ready ),
        .x_compressed_req_i     ( x_compressed_req   ),
        .x_compressed_resp_o    ( x_compressed_resp  ),

        // issue interface
        .x_issue_valid_i        ( x_issue_valid      ),
        .x_issue_ready_o        ( x_issue_ready      ),
        .x_issue_req_i          ( x_issue_req        ),
        .x_issue_resp_o         ( x_issue_resp       ),

        // commit interface
        .x_commit_valid_i       ( x_commit_valid     ),
        .x_commit_i             ( x_commit           ),

        // memory request/response interface
        .x_mem_valid_o          ( x_mem_valid        ),
        .x_mem_ready_i          ( x_mem_ready        ),
        .x_mem_req_o            ( x_mem_req          ),
        .x_mem_resp_i           ( x_mem_resp         ),

        // memory result interface
        .x_mem_result_valid_i   ( x_mem_result_valid ),
        .x_mem_result_i         ( x_mem_result       ),

        // result interface
        .x_result_valid_o       ( x_result_valid     ),
        .x_result_ready_i       ( x_result_ready     ),
        .x_result_o             ( x_result           )
    );

    quadrilatero_to_obi bridge_i (
        .clk_i      ( clk_i ),
        .rst_ni     ( rst_ni ),
        
        .mem_req_i      ( q_mem_req     ), 
        .mem_we_i       ( q_mem_we      ), 
        .mem_be_i       ( q_mem_be      ),
        .mem_addr_i     ( q_mem_addr    ), 
        .mem_wdata_i    ( q_mem_wdata   ),
        .mem_gnt_o      ( q_mem_gnt     ), 
        .mem_rvalid_o   ( q_mem_rvalid  ), 
        .mem_rdata_o    ( q_mem_rdata   ),
  
        .quadrilatero_ch0_req_o ( quad_req[0]   ), 
        .quadrilatero_ch0_resp_i( quad_resp[0]  ),
        .quadrilatero_ch1_req_o ( quad_req[1]   ), 
        .quadrilatero_ch1_resp_i( quad_resp[1]  ),
        .quadrilatero_ch2_req_o ( quad_req[2]   ), 
        .quadrilatero_ch2_resp_i( quad_resp[2]  ),
        .quadrilatero_ch3_req_o ( quad_req[3]   ), 
        .quadrilatero_ch3_resp_i( quad_resp[3]  )
);


    logic [4:0]       m_req, m_gnt, m_rvalid, m_we;
    logic [4:0][31:0] m_addr, m_wdata;
    logic [4:0][3:0]  m_be;
    logic [31:0]      arb_rdata;

    assign m_req[0]   = core_data_req;   assign m_we[0]    = core_data_we;
    assign m_addr[0]  = core_data_addr;  assign m_be[0]    = core_data_be;
    assign m_wdata[0] = core_data_wdata;
    assign core_data_gnt    = m_gnt[0];
    assign core_data_rvalid = m_rvalid[0];
    assign core_data_rdata  = arb_rdata;

    for (genvar i = 0; i < 4; i++) begin : g_quad
        assign m_req[i+1]   = quad_req[i].req;
        assign m_we[i+1]    = quad_req[i].we;
        assign m_be[i+1]    = quad_req[i].be;
        assign m_addr[i+1]  = quad_req[i].addr;
        assign m_wdata[i+1] = quad_req[i].wdata;
        assign quad_resp[i] = '{gnt: m_gnt[i+1], rvalid: m_rvalid[i+1], rdata: arb_rdata};
    end

    tb_mem_arb #(.N(5)) mem_arb_i (
      .clk(clk_i), 
      .rst_n(rst_ni),
      
      .m_req    ( m_req     ), 
      .m_gnt    ( m_gnt     ), 
      .m_rvalid ( m_rvalid  ),
      .m_addr   ( m_addr    ), 
      .m_we     ( m_we      ), 
      .m_be     ( m_be      ), 
      .m_wdata  ( m_wdata   ), 
      .m_rdata  ( arb_rdata ),
       
      .s_req    ( mem_req   ), 
      .s_gnt    ( mem_gnt   ), 
      .s_rvalid ( mem_rvalid),
      .s_addr   ( mem_addr  ), 
      .s_we     ( mem_we    ), 
      .s_be     ( mem_be    ), 
      .s_wdata  ( mem_wdata ), 
      .s_rdata  ( mem_rdata )
    );

endmodule // cv32e40p_core_tb_wrapper
