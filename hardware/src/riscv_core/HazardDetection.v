`include "Opcode.vh"

module HAZARD_DETECTION (
  input clk,
  input rst,
  input [6:0] opcode,
  input [4:0] if_id_rs1,
  input [4:0] if_id_rs2,
  input [4:0] id_ex_rd,

  input ctrl_pc_src,
  output ctrl_pc_en,
  output ctrl_imem_en,
  output ctrl_id_reg_flush,
  output ctrl_zero_sel
);

  wire inst_flush_value;

  // Imem use synchronous ram, so the flush control line output should use a register to 
  // be synchronized with the instruction.
  REGISTER #(.N(1)) inst_flush_reg (
    .clk(clk),
    .d(inst_flush_value),
    .q(ctrl_id_reg_flush)
  );

  // NOP
  assign ctrl_zero_sel = (opcode == 6'b0) || (!ctrl_pc_en);

  assign ctrl_pc_en = !(id_ex_rd != 0 && (if_id_rs1 == id_ex_rd || if_id_rs2 == id_ex_rd));
  assign ctrl_imem_en = rst || ctrl_pc_en;

  // Only when rst is high or imem is enabled and the pc value is updated from calculated one
  assign inst_flush_value = rst || (ctrl_imem_en & ctrl_pc_src);

endmodule