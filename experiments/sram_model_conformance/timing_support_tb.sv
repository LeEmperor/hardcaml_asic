`timescale 1ns/1ps

// Controlled simulator diagnostic for the same specify path-delay and timing-check
// constructs used by the candidate's non-FUNCTIONAL branch.
module timing_support_probe(
    input wire clock,
    input wire data,
    output wire result,
    output wire notifier_out
);
    reg stored = 1'b0;
    reg notifier = 1'b0;
    always @(posedge clock)
        stored <= data;
    assign result = stored;
    assign notifier_out = notifier;

    specify
        (clock => result) = (1.0, 1.0);
        $setup(data, posedge clock, 1.0, notifier);
    endspecify
endmodule

module timing_support_tb;
    reg clock = 1'b0;
    reg data = 1'b0;
    wire result;
    wire notifier;
    integer result_events = 0;

    timing_support_probe probe(
        .clock(clock),
        .data(data),
        .result(result),
        .notifier_out(notifier)
    );

    always #5ns clock = ~clock;
    always @(result) begin
        result_events = result_events + 1;
        $display("RESULT_EVENT time_ps=%0t value=%b", $time, result);
    end
    always @(notifier)
        $display("NOTIFIER_EVENT time_ps=%0t value=%b", $time, notifier);

    initial begin
        #2ns data = 1'b1;
        #3.5ns;
        $display("PATH_AT_0P5NS_AFTER_EDGE value=%b", result);
        #0.6ns;
        $display("PATH_AT_1P1NS_AFTER_EDGE value=%b", result);

        // Change data 0.2 ns before the next rising edge to violate the 1 ns setup.
        #8.7ns data = 1'b0;
        #1.3ns;
        $display("TIMING_CHECK_NOTIFIER value=%b", notifier);
        $display("DIAGNOSTIC result_events=%0d", result_events);
        $finish;
    end
endmodule
