`timescale 1ns/1ps

module tb_memory;
  reg [7:0] ui_in = 0;
  reg [7:0] uio_in = 0;
  reg ena = 0;
  reg clk = 0;
  reg rst_n = 1;
  wire [7:0] uo_out, uio_out, uio_oe;
  tt_um_asic_memory dut (.*);

  task cycle(input reg enable, input reg write, input reg [1:0] address,
             input reg [7:0] data);
    begin
      ena = enable;
      ui_in = {5'b0, write, address};
      uio_in = data;
      #5 clk = 1;
      #1;
      #4 clk = 0;
    end
  endtask

  initial begin
    cycle(1, 1, 0, 8'h36);
    cycle(1, 1, 1, 8'hc2);
    cycle(1, 0, 0, 0);
    if (uo_out !== 8'h36) $fatal(1, "memory word 0 readback");
    cycle(0, 0, 1, 0);
    if (uo_out !== 8'h36) $fatal(1, "memory disabled hold");
    cycle(1, 0, 1, 0);
    if (uo_out !== 8'hc2) $fatal(1, "memory word 1 readback");
    if (uio_out !== 0 || uio_oe !== 0) $fatal(1, "memory bidirectional pins");
    $display("memory bundle RTL passed");
    $finish;
  end
endmodule

module tb_observable;
  reg [7:0] ui_in = 0;
  reg [7:0] uio_in = 0;
  reg ena = 0;
  reg clk = 0;
  reg rst_n = 0;
  wire [7:0] uo_out, uio_out, uio_oe;
  tt_um_asic_observable dut (.*);

  initial begin
    #2 rst_n = 1;
    ena = 1;
    ui_in = 8'ha5;
    #5 clk = 1;
    #1;
    if (uo_out !== 8'ha5) $fatal(1, "observable capture");
    clk = 0;
    ena = 0;
    #1;
    if (uo_out !== 0) $fatal(1, "observable disable");
    if (uio_out !== 0 || uio_oe !== 0) $fatal(1, "observable bidirectional pins");
    $display("observable bundle RTL passed");
    $finish;
  end
endmodule
