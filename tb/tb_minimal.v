
`timescale 1ns/1ps

module tb_minimal;
  reg clk;
  initial clk = 0;
  always #1 clk = ~clk;

  initial begin
    $display("==========================================");
    $display(" AGNI: IcarusVerilog basic test");
    $display("==========================================");
    #10;
    $display("[PASS] IcarusVerilog is working!");
    $display("==========================================");
    $finish;
  end
endmodule
