`timescale 1ns/1ps
module t;
  logic [31:0] b;
  shortreal x,y;
  initial begin
    b = 32'h3f800000;
    x = $bitstoshortreal(b);
    y = $sin(x) + $cos(x) + $ln(x) + $exp(x) + $sqrt(x);
    $display("x=%f y=%f bits=%h", x, y, $shortrealtobits(y));
    $finish;
  end
endmodule
