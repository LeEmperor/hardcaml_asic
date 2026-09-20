`timescale 1ns/1ps

module sram_model_conformance_tb;
    reg         clock = 1'b0;
    reg         enable = 1'b0;
    reg         write_enable = 1'b0;
    reg  [7:0]  address = 8'h00;
    reg  [15:0] write_data = 16'h0000;
    wire [15:0] read_data;

    reg [15:0] expected_memory [0:255];
    reg        written [0:255];
    reg [15:0] prior_output;
    integer checks = 0;
    integer failures = 0;
    integer vectors = 0;
    integer index;

    RM_IHPSG13_1P_256x16_portable_wrapper dut (
        .clock(clock),
        .enable(enable),
        .write_enable(write_enable),
        .address(address),
        .write_data(write_data),
        .read_data(read_data)
    );

    always #5ns clock = ~clock;

    task automatic fail(input string message);
        begin
            failures = failures + 1;
            $display("FAIL t=%0t: %s", $time, message);
        end
    endtask

    task automatic check_case_equal(
        input [15:0] actual,
        input [15:0] expected,
        input string message
    );
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                $display("FAIL t=%0t: %s expected=%h actual=%h", $time, message, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task automatic check_fixed_controls;
        begin
            checks = checks + 1;
            if (dut.a_bm !== 16'hffff || dut.a_dly !== 1'b1 ||
                dut.a_bist_en !== 1'b0 || dut.a_bist_clk !== 1'b0 ||
                dut.a_bist_men !== 1'b0 || dut.a_bist_wen !== 1'b0 ||
                dut.a_bist_ren !== 1'b0 || dut.a_bist_addr !== 8'h00 ||
                dut.a_bist_din !== 16'h0000 || dut.a_bist_bm !== 16'h0000)
                fail("fixed mask, DLY, or BIST tie-off changed");
            checks = checks + 1;
            if (dut.a_wen === 1'b1 && dut.a_ren === 1'b1)
                fail("adapter requested simultaneous read/write");
        end
    endtask

    // Inputs change on the falling edge. The pre-edge comparison proves that
    // neither address nor control changes update the registered output early.
    task automatic drive_before_edge(
        input reg en,
        input reg we,
        input reg [7:0] addr,
        input reg [15:0] data
    );
        reg [15:0] previous_output;
        begin
            @(negedge clock);
            previous_output = read_data;
            enable = en;
            write_enable = we;
            address = addr;
            write_data = data;
            #1ns;
            check_case_equal(read_data, previous_output, "output changed before sampling edge");
            check_fixed_controls();
        end
    endtask

    task automatic sample_edge;
        begin
            @(posedge clock);
`ifdef TIMED_MODEL
            #2;
`else
            // The vendor model uses nonblocking assignments at the sampling
            // edge. Its 10 ps precision makes this 100 ps delay race-free.
            #0.1;
`endif
        end
    endtask

    task automatic write_word(input reg [7:0] addr, input reg [15:0] data);
        begin
            vectors = vectors + 1;
            drive_before_edge(1'b1, 1'b1, addr, data);
            sample_edge();
            expected_memory[addr] = data;
            written[addr] = 1'b1;
            // Output is deliberately not constrained after a write.
            prior_output = read_data;
        end
    endtask

    task automatic read_written(input reg [7:0] addr);
        begin
            vectors = vectors + 1;
            if (!written[addr])
                fail("testbench attempted a defined comparison on an unwritten address");
            drive_before_edge(1'b1, 1'b0, addr, 16'h0000);
            sample_edge();
            check_case_equal(read_data, expected_memory[addr], "defined read mismatch");
            prior_output = read_data;
        end
    endtask

    task automatic read_unwritten(input reg [7:0] addr);
        begin
            vectors = vectors + 1;
            if (written[addr])
                fail("testbench attempted an unspecified read on a written address");
            drive_before_edge(1'b1, 1'b0, addr, 16'h0000);
            sample_edge();
            // Any four-state value is legal. Save the actual value for hold checking.
            prior_output = read_data;
        end
    endtask

    task automatic disabled_cycle(
        input reg we,
        input reg [7:0] addr,
        input reg [15:0] data
    );
        begin
            vectors = vectors + 1;
            prior_output = read_data;
            drive_before_edge(1'b0, we, addr, data);
            sample_edge();
            check_case_equal(read_data, prior_output, "disabled output did not hold");
            prior_output = read_data;
        end
    endtask

    initial begin
        for (index = 0; index < 256; index = index + 1)
            written[index] = 1'b0;

`ifdef INJECT_FAILURE
        #1ns;
        $fatal(1, "intentional failure-path sanity check");
`endif

        // No reset or initialization is applied. The initial output may be any
        // four-state value; only preservation across a disabled edge is required.
        #1ns;
        prior_output = read_data;
        disabled_cycle(1'b1, 8'h80, 16'h9669);

        read_unwritten(8'h7e);
        disabled_cycle(1'b0, 8'hff, 16'hffff);

        // Complementary rewrites expose a stuck-low, inactive, or partial mask.
        write_word(8'h00, 16'ha55a);
        disabled_cycle(1'b1, 8'h00, 16'h5aa5);
        read_written(8'h00);
        write_word(8'h00, 16'h5aa5);
        read_written(8'h00);

        // Consecutive writes and reads, including first and last legal addresses.
        write_word(8'hff, 16'h0000);
        write_word(8'h01, 16'hffff);
        read_written(8'h00);
        read_written(8'hff);
        read_written(8'h01);

        // Disabled write-like inputs must neither change output nor memory.
        disabled_cycle(1'b1, 8'hff, 16'hffff);
        read_written(8'hff);

        // Same-address read/write and write/read transitions.
        read_written(8'h00);
        write_word(8'h00, 16'h0f0f);
        disabled_cycle(1'b0, 8'h55, 16'hf00f);
        read_written(8'h00);
        write_word(8'h3c, 16'hc33c);
        read_written(8'h3c);

        // Re-establish an unspecified result and prove exact X/Z-aware hold.
        read_unwritten(8'hfe);
        disabled_cycle(1'b1, 8'h3c, 16'h3cc3);
        check_fixed_controls();

        $display("RESULT vectors=%0d checks=%0d failures=%0d", vectors, checks, failures);
        if (failures != 0)
            $fatal(1, "SRAM contract conformance failed");
        $display("PASS exact candidate satisfies the checked portable RAM functional contract");
        $finish;
    end
endmodule
