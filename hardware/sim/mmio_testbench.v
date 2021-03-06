`timescale 1ns/1ns

module mmio_testbench;

  reg clk, rst;
  parameter CPU_CLOCK_PERIOD = 20;
  parameter CPU_CLOCK_FREQ = 1_000_000_000 / CPU_CLOCK_PERIOD;

  initial clk = 0;
  always #(CPU_CLOCK_PERIOD / 2) clk = ~clk;
  wire [31:0] csr;

  Riscv151 # (
    .CPU_CLOCK_FREQ(CPU_CLOCK_FREQ),
    .RESET_PC(32'h1000_0000)
  ) CPU (
    .clk(clk),
    .rst(rst),
    .FPGA_SERIAL_RX(),
    .FPGA_SERIAL_TX(),
    .csr(csr)
  );

  task reset;
    integer i;
    begin
      for (i = 0; i < `RF_PATH.DEPTH; i = i + 1) begin
        `RF_PATH.mem[i] = 0;
      end
      for (i = 0; i < `DMEM_PATH.DEPTH; i = i + 1) begin
        `DMEM_PATH.mem[i] = 0;
      end
      for (i = 0; i < `RF_PATH.DEPTH; i = i + 1) begin
        `RF_PATH.mem[i] = 0;
      end
      
      @(negedge clk);
      rst = 1;
      @(negedge clk);
      rst = 0;
    end
  endtask

  reg [31:0] cycle;
  reg done;
  reg [31:0]  current_test_id = 0;
  reg [255:0] current_test_type;
  reg [31:0]  current_output;
  reg [31:0]  current_result;
  reg all_tests_passed = 0;

  wire [31:0] timeout_cycle = 13;
  
  // Check for timeout
  // If a test does not return correct value in a given timeout cycle,
  // we terminate the testbench
  initial begin
    while (all_tests_passed === 0) begin
      @(posedge clk);
      if (cycle === timeout_cycle) begin
        $display("[Failed] Timeout at [%d] test %s, expected_result = %h, got = %h",
                current_test_id, current_test_type, current_result, current_output);
        $finish();
      end
    end
  end

  always @(posedge clk) begin
    if (done === 0)
      cycle <= cycle + 1;
    else
      cycle <= 0;
  end  

  // Check result of RegFile
  // If the write_back (destination) register has correct value (matches "result"), test passed
  // This is used to test instructions that update RegFile
  task check_result_rf;
    input [31:0]  rf_wa;
    input [31:0]  result;
    input [255:0] test_type;
    begin
      done = 0;
      current_test_id   = current_test_id + 1;
      current_test_type = test_type;
      current_result    = result;
      while (`RF_PATH.mem[rf_wa] !== result) begin
        current_output = `RF_PATH.mem[rf_wa];
        @(posedge clk);
      end
      done = 1;
      $display("[%d] Test %s passed!, time: %d", current_test_id, test_type, $time);
    end
  endtask

  integer i;

  reg [31:0] IMM0, IMM;
  reg [14:0] INST_ADDR;
  reg [31:0] CYCLE_COUNTER_ADDR, COUNTER_RESET_ADDR, INST_COUNTER_ADDR;

  initial begin
    $dumpfile("mmio_testbench.vcd");
    $dumpvars;
    
    #0;
    rst = 0;
    
    // Reset the CPU
    rst = 1;
    // Hold reset for a while
    repeat (10) @(posedge clk);

    @(negedge clk);
    rst = 0;

    reset();

    // Test Cycle Counter;
    INST_ADDR = 14'h0000;
    IMM0      = 32'd0;
    CYCLE_COUNTER_ADDR = 32'h80000010;
    INST_COUNTER_ADDR  = 32'h80000014;
    COUNTER_RESET_ADDR = 32'h80000018;

    `RF_PATH.mem[1] = COUNTER_RESET_ADDR;
    `RF_PATH.mem[2] = CYCLE_COUNTER_ADDR;
    
    // Reset the counter
    `IMEM_PATH.mem[INST_ADDR + 0] = {IMM0[11:5], 5'd0, 5'd1, `FNC_SW, IMM0[4:0], `OPC_STORE};
    `IMEM_PATH.mem[INST_ADDR + 1] = {IMM0[11:5], 5'd2, `FNC_LW, 5'd3, `OPC_LOAD};
    `IMEM_PATH.mem[INST_ADDR + 4] = {IMM0[11:0], 5'd2, `FNC_LW, 5'd4, `OPC_LOAD};
    `IMEM_PATH.mem[INST_ADDR + 10] = {IMM0[11:0], 5'd2, `FNC_LW, 5'd5, `OPC_LOAD};

    check_result_rf(5'd3, 32'd0, "Cycle counter reset");
    check_result_rf(5'd4, 32'd3, "Cycle counter after 3 cycles");
    check_result_rf(5'd5, 32'd9, "Cycle counter after 9 cycles");

    reset();
    
    `RF_PATH.mem[1] = COUNTER_RESET_ADDR; 
    `RF_PATH.mem[2] = INST_COUNTER_ADDR;
    `RF_PATH.mem[3] = -100;
    `RF_PATH.mem[4] = 200;

    IMM             = 32'h0000_0004;

    `IMEM_PATH.mem[INST_ADDR + 0] = {IMM0[11:5], 5'd0, 5'd1, `FNC_SW, IMM0[4:0], `OPC_STORE};
    `IMEM_PATH.mem[INST_ADDR + 1] = {IMM0[11:5], 5'd2, `FNC_LW, 5'd5, `OPC_LOAD};
    `IMEM_PATH.mem[INST_ADDR + 2] = {`FNC7_0, 5'd4, 5'd3, `FNC_ADD_SUB, 5'd0, `OPC_ARI_RTYPE};
    `IMEM_PATH.mem[INST_ADDR + 3] = {IMM0[11:5], 5'd2, `FNC_LW, 5'd6, `OPC_LOAD};
    `IMEM_PATH.mem[INST_ADDR + 4] = {IMM[20], IMM[10:1], IMM[11], IMM[19:12], 5'd3, `OPC_JAL};
    `IMEM_PATH.mem[INST_ADDR + 5] = {`FNC7_0, 5'd4, 5'd3, `FNC_ADD_SUB, 5'd0, `OPC_ARI_RTYPE};
    `IMEM_PATH.mem[INST_ADDR + 6] = {IMM0[11:5], 5'd2, `FNC_LW, 5'd7, `OPC_LOAD};

    // check_result_rf(5'd5, 32'd0, "Inst counter reset");
    check_result_rf(5'd6, 32'd2, "One instruction execution");
    check_result_rf(5'd7, 32'd5, "Bubble instruction execution");

    all_tests_passed = 1'b1;

    #100;
    $display("All tests passed!");
    $finish();
  end

endmodule