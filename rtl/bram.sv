`timescale 1ns / 1ps

// dual-port, synchronous read and write

module bram #(
    parameter WIDTH = 32,
    parameter DEPTH = 1024, // power of 2
    parameter MEM_FILE = ""
    ) (
    // port 0
    input logic i_clk_0,
    input logic i_wr_en_0,
    input logic [$clog2(DEPTH)-1:0] i_addr_0,
    input logic [WIDTH-1:0] i_wr_data_0,
    output logic [WIDTH-1:0] o_rd_data_0,

    // port 1
    input logic i_clk_1,
    input logic i_wr_en_1,
    input logic [$clog2(DEPTH)-1:0] i_addr_1,
    input logic [WIDTH-1:0] i_wr_data_1,
    output logic [WIDTH-1:0] o_rd_data_1
    );

    (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

    initial begin
        if (MEM_FILE != "") begin
            $readmemh(MEM_FILE, mem);
        end
    end

    // port 0
    always_ff @(posedge i_clk_0) begin
        if (i_wr_en_0)
            mem[i_addr_0] <= i_wr_data_0;
        else
            o_rd_data_0 <= mem[i_addr_0];
    end

    // port 1
    always_ff @(posedge i_clk_1) begin
        if (i_wr_en_1)
            mem[i_addr_1] <= i_wr_data_1;
        else
            o_rd_data_1 <= mem[i_addr_1];
    end

endmodule
