`timescale 1ns / 1ps

// dual-port, synchronous read and write

module bram #(
    parameter MEM_FILE = ""
    ) (
    input i_clk,
    input [1:0] i_wr_en,
    input [9:0] i_addr [0:1],
    input [31:0] i_wr_data [0:1],
    output logic [31:0] o_rd_data [0:1]
    );

    logic [31:0] mem [0:1023];

    initial begin
        if (MEM_FILE != "") begin
            $readmemh(MEM_FILE, mem);
        end
        else begin
            $readmemh("zeros.mem", mem);
        end
    end

    // port 0
    always_ff @(posedge i_clk) begin
        if (i_wr_en[0])
            mem[i_addr[0]] <= i_wr_data[0];
        else
            o_rd_data[0] <= mem[i_addr[0]];
    end

    // port 1
    always_ff @(posedge i_clk) begin
        if (i_wr_en[1])
            mem[i_addr[1]] <= i_wr_data[1];
        else
            o_rd_data[1] <= mem[i_addr[1]];
    end

endmodule
