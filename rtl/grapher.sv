`timescale 1ns / 1ps




module grapher (
    input i_clk_25MHz,
    input i_rst,
    input i_en,
    input i_hs,
    input i_vs,
    input [9:0] i_x_pos,
    input [8:0] i_y_pos,
    input i_active_video,
    input [31:0] i_rd_data,
    output logic [9:0] o_rd_addr,
    output o_draw
);

// grapher

logic r_green = 0;
logic draw;
logic [8:0] x_pos_graph;
logic [8:0] y_pos_graph;
logic [8:0] r_y_pos_graph;
logic [8:0] r_x_pos_graph;

/*
read memory at address x_pos + offset x - takes 1 clk cycle
compare data with y_pos + offset y
if same, colour
*/

// read memory
localparam X_START_GRAPH = 64;
localparam GRAPH_WIDTH = 512;
localparam X_END_GRAPH = X_START_GRAPH + GRAPH_WIDTH;
localparam Y_START_GRAPH = 200;
localparam GRAPH_HEIGHT = 256;
localparam Y_END_GRAPH = Y_START_GRAPH + GRAPH_HEIGHT;

/*

1st clk cycle

send out rd en and rd addr and determine graph positions

*/
logic active_graph;
logic r_active_graph;

always_comb begin
    if ((i_active_video) && 
        (i_x_pos >= X_START_GRAPH) && (i_x_pos < X_END_GRAPH) &&
        (i_y_pos >= Y_START_GRAPH) && (i_y_pos < Y_END_GRAPH)) begin

        active_graph = 1;
        x_pos_graph = i_x_pos - X_START_GRAPH;
        y_pos_graph = i_y_pos - Y_START_GRAPH;

        o_rd_addr = {1'b0, x_pos_graph};
    end
    else begin
        active_graph = 0;
        x_pos_graph = 0;
        y_pos_graph = 0;
        o_rd_addr = 0;
    end
end

/*

2nd clk cycle

rd data is available

calculate the magnitude and compare to y pos graph (prev cycle)

*/
// register y pos graph
always_ff @(posedge i_clk_25MHz) begin
    if (i_rst) begin
        r_y_pos_graph <= 0;
        r_x_pos_graph <= 0;
        r_active_graph <= 0;
    end
    else if (i_en) begin
        r_y_pos_graph <= y_pos_graph;
        r_x_pos_graph <= x_pos_graph;
        r_active_graph <= active_graph;
    end
end
wire signed [15:0] re_data = i_rd_data[15:0];
wire signed [15:0] im_data = i_rd_data[31:16];
logic [15:0] abs_rd_data [0:1];
logic [16:0] sum_abs_rd_data;
logic [8:0] scaled_abs_rd_data;

always_comb begin

    if (re_data[15]) begin //  if negative
        abs_rd_data[0] = -re_data;
    end
    else begin
        abs_rd_data[0] = re_data;
    end

    if (im_data[15]) begin //  if negative
        abs_rd_data[1] = -im_data;
    end
    else begin
        abs_rd_data[1] = im_data;
    end

    sum_abs_rd_data = abs_rd_data[0] + abs_rd_data[1];

    scaled_abs_rd_data = sum_abs_rd_data >> 2; // max 255
end

// compare 
always_comb begin
    if (r_active_graph) begin
        // draw = 1; // colour in the graph area

        if ((r_y_pos_graph == 9'd255) ||
            (r_x_pos_graph == 9'd0) ||
            (r_y_pos_graph == (GRAPH_HEIGHT - scaled_abs_rd_data))) begin

            draw = 1;
        end
        else begin
            draw = 0;
        end
    end
    else begin
        draw = 0;
    end
end

/*

3rd clk cycle

*/
always_ff @(posedge i_clk_25MHz) begin
    if (i_rst) begin
        r_green <=0;
    end
    else if (i_en) begin
        r_green <= draw;
    end
end

assign o_draw = r_green;

endmodule
