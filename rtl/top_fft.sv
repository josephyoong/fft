`timescale 1ns / 1ps



module top_fft(
    input CLK100MHZ,
    input M_DATA,
    output [3:0] VGA_R,
    output [3:0] VGA_G,
    output [3:0] VGA_B,
    output VGA_HS,
    output VGA_VS,
    output led0,
    output M_CLK,
    output M_LRSEL
);

wire g0;
wire vga_clk;
wire locked;
wire clk;
logic [7:0] counter = '0;
wire start_fft;
wire start_graph;
wire load;

clk_wiz_0 clk_wiz_0_inst (
  .clk_out1(vga_clk),
  .clk_out2(clk),
  .reset(1'b0),
  .locked(locked),
  .clk_in1(CLK100MHZ)
);

always_ff @(posedge vga_clk) begin
    if (~locked) begin
        counter <= '0;
    end
    else begin
        if (counter == 8'hFF) begin
            counter <= counter;
        end
        else begin
            counter <= counter + 1;
        end
    end
end

assign start_fft = 1'b0; //(counter == 8'd10); // cdc

assign start_graph = 1'b0; //(counter == 8'hFF); // cdc

assign load = (counter == 8'hFF);

fft fft0 (
    .i_clk(clk),
    .i_clk_25MHz(vga_clk),
    .i_rst(~locked),
    .i_en(1'b1),
    .i_start_fft(start_fft),
    .i_start_graph(start_graph),
    .i_load(load),
    .i_mic_data(M_DATA),
    .o_busy(led0),
    .o_hs(VGA_HS),
    .o_vs(VGA_VS),
    .o_g0(g0),
    .o_mic_clk(M_CLK),
    .o_lrsel(M_LRSEL)
);

assign VGA_R = '0;
assign VGA_G = {4{g0}};
assign VGA_B = '0;

endmodule
