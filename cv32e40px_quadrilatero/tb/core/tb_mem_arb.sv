module tb_mem_arb #(
  parameter int N = 5            // 0 = core, 1..4 = quadrilatero
)(
  input  logic clk, rst_n,
  // master
  input  logic [N-1:0]        m_req,
  output logic [N-1:0]        m_gnt,
  output logic [N-1:0]        m_rvalid,
  input  logic [N-1:0][31:0]  m_addr,
  input  logic [N-1:0]        m_we,
  input  logic [N-1:0][3:0]   m_be,
  input  logic [N-1:0][31:0]  m_wdata,
  output logic [31:0]         m_rdata, 
  // slave (mm_ram)
  output logic                s_req,
  input  logic                s_gnt,
  input  logic                s_rvalid,
  output logic [31:0]         s_addr,
  output logic                s_we,
  output logic [3:0]          s_be,
  output logic [31:0]         s_wdata,
  input  logic [31:0]         s_rdata
);
  localparam int W = $clog2(N);
  logic [W-1:0] sel, owner;
  logic         any_req;

  // fixed priority: lower index has higher priority
  always_comb begin
    sel = '0; any_req = 1'b0;
    for (int i = N-1; i >= 0; i--)
      if (m_req[i]) begin sel = W'(i); any_req = 1'b1; end
  end

  assign s_req   = any_req;
  assign s_addr  = m_addr[sel];
  assign s_we    = m_we[sel];
  assign s_be    = m_be[sel];
  assign s_wdata = m_wdata[sel];

  always_comb begin
    m_gnt = '0;
    if (any_req && s_gnt) m_gnt[sel] = 1'b1;
  end

  // response: no FIFO, valid only with 1 request in flight
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) owner <= '0;
    else if (any_req && s_gnt) owner <= sel;

  always_comb begin
    m_rvalid = '0;
    m_rvalid[owner] = s_rvalid;
  end
  assign m_rdata = s_rdata;
endmodule