`timescale 1ns / 1ps



module vga (
    input i_clk_25MHz,
    output logic o_hs,
    output logic o_vs,
    output logic o_active_video,
    output logic [9:0]  o_x_pos,
    output logic [8:0]  o_y_pos
);

    logic [9:0] h_counter = 10'd0;
    logic [9:0] v_counter = 10'd0;

    // counters
    always_ff @(posedge i_clk_25MHz) begin
        if (h_counter == 10'd799) begin
            h_counter <= 10'd0;
            v_counter <= (v_counter == 10'd524) ? 10'd0 : v_counter + 1;
        end
        else begin
            h_counter <= h_counter + 1;
        end
    end

    // sync signals
    always_ff @(posedge i_clk_25MHz) begin
        o_hs <= ~((h_counter >= 656) && (h_counter <= 751));
        o_vs <= ~((v_counter >= 490) && (v_counter <= 491));
    end

    // active video and position
    assign o_active_video = (h_counter < 640) && (v_counter < 480);
    assign o_x_pos = o_active_video ? h_counter : 10'd0;
    assign o_y_pos = o_active_video ? v_counter[8:0] : 9'd0;

endmodule