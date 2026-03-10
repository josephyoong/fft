`timescale 1ns / 1ps



module rom(
    input i_clk,
    input [8:0] i_addr,
    output logic [31:0] o_rd_data
    );

    logic [31:0] mem [0:511];

    initial begin
        $readmemh("twiddle.mem", mem);
    end

    always_ff @(posedge i_clk) begin
        o_rd_data <= mem[i_addr];
    end

endmodule
