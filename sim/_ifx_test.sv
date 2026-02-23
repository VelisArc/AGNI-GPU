module t;
  reg x;
  initial begin
    x = 1'bx;
    if (x) $display("THEN"); else $display("ELSE");
  end
endmodule
