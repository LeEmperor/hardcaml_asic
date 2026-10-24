`timescale 1ns/10ps
module contract_tb;
  reg clock = 0;
  reg enable = 0;
  reg write_enable = 0;
  reg [7:0] address = 0;
  reg [15:0] write_data = 0;
  wire [15:0] read_data;
  sram_backend_top dut (
    .clock(clock), .enable(enable), .write_enable(write_enable),
    .address(address), .write_data(write_data), .read_data(read_data)
  );

  reg [15:0] stored [0:255];
  reg [255:0] known = 0;
  integer edges = 0;
  integer checks = 0;
  integer n;
  integer a;
  reg [15:0] data;

  task step;
    input en;
    input wr;
    input [7:0] addr;
    input [15:0] din;
    reg [15:0] prior;
    reg [15:0] expected;
    begin
      prior = read_data;
      enable = en;
      write_enable = wr;
      address = addr;
      write_data = din;
      #4;
      // The portable output must not respond before the sampling edge.
      if (read_data !== prior)
        $fatal(1, "output changed before edge %0d", edges);
`ifdef CHECK_MACRO
      if (dut.hc_resource_7_program.A_CLK !== clock ||
          dut.hc_resource_7_program.A_MEN !== en ||
          dut.hc_resource_7_program.A_WEN !== (en && wr) ||
          dut.hc_resource_7_program.A_REN !== (en && !wr) ||
          dut.hc_resource_7_program.A_ADDR !== addr ||
          dut.hc_resource_7_program.A_DIN !== din ||
          dut.hc_resource_7_program.A_DLY !== 1'b1 ||
          dut.hc_resource_7_program.A_BM !== 16'hffff ||
          dut.hc_resource_7_program.A_BIST_CLK !== 1'b0 ||
          dut.hc_resource_7_program.A_BIST_EN !== 1'b0 ||
          dut.hc_resource_7_program.A_BIST_MEN !== 1'b0 ||
          dut.hc_resource_7_program.A_BIST_WEN !== 1'b0 ||
          dut.hc_resource_7_program.A_BIST_REN !== 1'b0 ||
          dut.hc_resource_7_program.A_BIST_ADDR !== 8'h00 ||
          dut.hc_resource_7_program.A_BIST_DIN !== 16'h0000 ||
          dut.hc_resource_7_program.A_BIST_BM !== 16'h0000)
        $fatal(1, "macro control, width or tie-off error at edge %0d", edges);
`endif
      clock = 1;
      #1;
      if (!en) begin
        // Includes hold after writes/unwritten reads/initial unknown output.
        if (read_data !== prior)
          $fatal(1, "disabled hold failed at edge %0d", edges);
        checks = checks + 1;
      end else if (wr) begin
        stored[addr] = din;
        known[addr] = 1;
      end else if (known[addr]) begin
        expected = stored[addr];
`ifdef INJECT_FAILURE
        expected = expected ^ 16'h0001;
`endif
        if (read_data !== expected)
          $fatal(1, "read/latency failed at edge %0d addr %0d: expected %h got %h",
                 edges, addr, expected, read_data);
        checks = checks + 1;
      end
      edges = edges + 1;
      #4 clock = 0;
      #1;
    end
  endtask

  initial begin
    #1;
    step(0, 0, 0, 0);
    step(1, 0, 3, 0); // Unwritten read: no prescribed result.
    step(0, 1, 3, 16'hffff);
    for (n = 0; n < 256; n = n + 1) begin
      data = (n * 257) ^ 16'ha53c;
      step(1, 1, n, data);
      step(0, 0, n ^ 8'hff, ~data); // Hold each backend's actual write output.
    end
    for (n = 0; n < 256; n = n + 1) begin
      a = (n * 73 + 19) & 255;
      step(1, 0, a, 0);
      step(1, 0, (a + 1) & 255, 0); // Consecutive reads catch extra latency.
      step(0, 0, a, 0);
      step(0, 1, a, ~stored[a]); // Disabled write must not modify storage.
    end
    for (n = 255; n >= 0; n = n - 1)
      step(1, 0, n, 0);
    for (n = 0; n < 256; n = n + 1) begin
      data = (n & 1) ? 16'hffff : 16'h0000;
      step(1, 1, n, data);
      step(1, 0, n, 0);
    end
    $display("PASS contract: %0d edges, %0d defined-read/hold checks", edges, checks);
    $finish;
  end
endmodule
