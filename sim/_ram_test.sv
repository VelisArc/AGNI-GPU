`timescale 1ns/1ps
module t;
  logic clk=0,en=1,we=0; logic [9:0] addr=0; logic [31:0] wdata=0,rdata; logic ce,ue;
  always #1 clk=~clk;
  ram_sp #(.WIDTH(32),.DEPTH(1024),.ECC_EN(1'b1)) u(.clk(clk),.en(en),.we(we),.addr(addr),.wdata(wdata),.rdata(rdata),.ecc_error(ce),.ecc_ue(ue));
  initial begin
    repeat(5) @(posedge clk);
    $display("ce=%b ue=%b rdata=%h", ce, ue, rdata);
    $finish;
  end
endmodule
