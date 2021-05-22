`define FORWARD_EX 2'b01;
`define FORWARD_WB 2'b10;

module FORWARD #(
  parameter DWIDTH = 32
) (
  input [4:0] rs1_addr_id,
  input [4:0] rs2_addr_id,
  input [4:0] rd_addr_ex_in,
  input [4:0] rd_addr_id_in,
  input ctrl_reg_we_ex_in,
  input ctrl_reg_we_id_in,
  output ex_forward_a_sel,
  output ex_forward_b_sel,
  output id_forward_a_sel,
  output id_forward_b_sel
);

  reg ex_forward_a_sel, ex_forward_b_sel;
  reg id_forward_a_sel, id_forward_b_sel;

  // EX Hazard
  always @(*) begin
    if (ctrl_reg_we_ex_in && rs1_addr_id == rd_addr_ex_in && rd_addr_ex_in != 5'd0) begin
      ex_forward_a_sel = 1'b1;
    end else begin
      ex_forward_a_sel = 1'b0;
    end
  end

  always @(*) begin
    if (ctrl_reg_we_ex_in && rs2_addr_id == rd_addr_ex_in && rd_addr_ex_in != 5'd0) begin
      ex_forward_b_sel = 1'b1;
    end else begin
      ex_forward_b_sel = 1'b0;
    end
  end

  always @(*) begin
    if (ctrl_reg_we_id_in && rs1_addr_id == rd_addr_id_in && rd_addr_id_in != 5'd0) begin
      id_forward_a_sel = 1'b1;
    end else begin
      id_forward_a_sel = 1'b0;
    end
  end

  always @(*) begin
    if (ctrl_reg_we_id_in && rs2_addr_id == rd_addr_id_in && rd_addr_id_in != 5'd0) begin
      id_forward_b_sel = 1'b1;
    end else begin
      id_forward_b_sel = 1'b0;
    end
  end
endmodule
