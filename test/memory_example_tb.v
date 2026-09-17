`timescale 1ns/1ps

module memory_example_tb;
  reg clock = 0;
  reg enable = 0;
  reg write_enable = 0;
  reg [1:0] address = 0;
  reg [7:0] write_data = 0;
  wire [7:0] read_data;
  reg [7:0] held;

  memory_example dut (
    .clock(clock),
    .enable(enable),
    .write_enable(write_enable),
    .address(address),
    .write_data(write_data),
    .read_data(read_data)
  );

  always #5 clock = ~clock;

  task step(input reg en, input reg wr, input reg [1:0] addr, input reg [7:0] data);
    begin
      @(negedge clock);
      enable = en;
      write_enable = wr;
      address = addr;
      write_data = data;
      @(posedge clock);
      #1;
    end
  endtask

  task check(input reg [7:0] expected);
    begin
      if (read_data !== expected)
        $fatal(1, "read_data=%h expected=%h", read_data, expected);
    end
  endtask

  initial begin
    step(1, 1, 0, 8'h36);
    held = read_data;
    step(0, 1, 1, 8'hff);
    if (read_data !== held)
      $fatal(1, "disabled cycle after write did not hold output");
    step(1, 1, 1, 8'hc2);
    step(1, 0, 0, 0);
    check(8'h36);
    step(0, 0, 2, 0);
    check(8'h36);
    step(1, 0, 1, 0);
    check(8'hc2);
    step(1, 1, 0, 8'ha4);
    step(1, 0, 0, 0);
    check(8'ha4);
    step(0, 0, 1, 0);
    check(8'ha4);
    $display("generated flop RTL: write, read, and hold passed");
    $finish;
  end
endmodule
