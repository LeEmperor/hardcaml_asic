`timescale 1ns/1ps

// Experimental S.2a adapter only. This is not a registered technology mapping.
module RM_IHPSG13_1P_256x16_portable_wrapper (
    input  wire        clock,
    input  wire        enable,
    input  wire        write_enable,
    input  wire [7:0]  address,
    input  wire [15:0] write_data,
    output wire [15:0] read_data
);
    wire        a_men = enable;
    wire        a_wen = enable && write_enable;
    wire        a_ren = enable && !write_enable;
    wire [15:0] a_bm = 16'hffff;
    wire        a_dly = 1'b1;

    // BIST selection never changes. Stable zeroes make every unused BIST
    // request, address, data, mask, and clock input inactive.
    wire        a_bist_en = 1'b0;
    wire        a_bist_clk = 1'b0;
    wire        a_bist_men = 1'b0;
    wire        a_bist_wen = 1'b0;
    wire        a_bist_ren = 1'b0;
    wire [7:0]  a_bist_addr = 8'h00;
    wire [15:0] a_bist_din = 16'h0000;
    wire [15:0] a_bist_bm = 16'h0000;

    RM_IHPSG13_1P_256x16_c2_bm_bist macro (
        .A_CLK(clock),
        .A_MEN(a_men),
        .A_WEN(a_wen),
        .A_REN(a_ren),
        .A_ADDR(address),
        .A_DIN(write_data),
        .A_DLY(a_dly),
        .A_DOUT(read_data),
        .A_BM(a_bm),
        .A_BIST_CLK(a_bist_clk),
        .A_BIST_EN(a_bist_en),
        .A_BIST_MEN(a_bist_men),
        .A_BIST_WEN(a_bist_wen),
        .A_BIST_REN(a_bist_ren),
        .A_BIST_ADDR(a_bist_addr),
        .A_BIST_DIN(a_bist_din),
        .A_BIST_BM(a_bist_bm)
    );
endmodule
