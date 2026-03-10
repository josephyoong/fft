`timescale 1ns / 1ps

/*

   .==-.                   .-==.
   \()8`-._  `.   .'  _.-'8()/
   (88"   ::.  \./  .::   "88)
    \_.'`-::::.(#).::::-'`._/
      `._... .q(_)p. ..._.'
        ""-..-'|=|`-..-""
              ,|=|.
             ((/^\))

even + (odd * twi) = top
even - (odd * twi) = btm

5 clk latency

1-bit bit growth: 
    0-bit growth from multiplication since |twi| < 1
    1-bit growth from addition

*/

module butterfly #(
    parameter I = 1, // Q I.F format
    parameter F = 15
    ) (
    input i_clk,
    input i_en,
    input i_rst,
    input signed [15:0] i_even [0:1],
    input signed [15:0] i_odd [0:1],
    input signed [15:0] i_twi [0:1],
    output signed [15:0] o_top [0:1],
    output signed [15:0] o_btm [0:1]
    );

    // register inputs: CLK1
    logic signed [15:0] even [0:1];
    logic signed [15:0] odd [0:1];
    logic signed [15:0] twi [0:1];
    always_ff @(posedge i_clk) begin
        for (int i=0; i<2; i++) begin
            if (i_rst) begin
                even[i] <= '0;
                odd[i] <= '0;
                twi[i] <= '0;
            end
            else if (i_en) begin
                even[i] <= i_even[i];
                odd[i] <= i_odd[i];
                twi[i] <= i_twi[i];
            end
        end
    end

    // odd * twi = (a+bi) * (c+di) = (ac-bd) + (ad+bc)i

    // ac, bd, ad, bc: CLK2
    logic signed [31:0] ac_32;
    logic signed [31:0] bd_32;
    logic signed [31:0] ad_32;
    logic signed [31:0] bc_32;
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            ac_32 <= '0;
            bd_32 <= '0;
            ad_32 <= '0;
            bc_32 <= '0;
        end
        else if (i_en) begin
            // ac_32 <= odd[0] * twi[0]; // four 16-bit multipliers
            // bd_32 <= odd[1] * twi[1];
            // ad_32 <= odd[0] * twi[1];
            // bc_32 <= odd[1] * twi[0];
            ac_32 <= $signed(odd[0]) * $signed(twi[0]);
            bd_32 <= $signed(odd[1]) * $signed(twi[1]);
            ad_32 <= $signed(odd[0]) * $signed(twi[1]);
            bc_32 <= $signed(odd[1]) * $signed(twi[0]);
        end
    end

    // truncate, round and truncate: CLK3
    wire signed [16:0] ac_17 = ac_32[31-I:F-1]; // truncate
    wire signed [16:0] bd_17 = bd_32[31-I:F-1]; // Q2.15
    wire signed [16:0] ad_17 = ad_32[31-I:F-1];
    wire signed [16:0] bc_17 = bc_32[31-I:F-1];
    // logic signed [16:0] ac_rnd;
    // logic signed [16:0] bd_rnd;
    // logic signed [16:0] ad_rnd;
    // logic signed [16:0] bc_rnd;
    // always_ff @(posedge i_clk) begin
    //     if (i_rst) begin
    //         ac_rnd <= '0;
    //         bd_rnd <= '0;
    //         ad_rnd <= '0;
    //         bc_rnd <= '0;
    //     end
    //     else if (i_en) begin
    //         ac_rnd <= ac_17 + 1; // round
    //         bd_rnd <= bd_17 + 1;
    //         ad_rnd <= ad_17 + 1;
    //         bc_rnd <= bc_17 + 1;
    //     end
    // end

    logic signed [17:0] ac_rnd;
    logic signed [17:0] bd_rnd;
    logic signed [17:0] ad_rnd;
    logic signed [17:0] bc_rnd;

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            ac_rnd <= '0;
            bd_rnd <= '0;
            ad_rnd <= '0;
            bc_rnd <= '0;
        end
        else if (i_en) begin
            ac_rnd <= 18'(ac_17) + 18'd1;
            bd_rnd <= 18'(bd_17) + 18'd1;
            ad_rnd <= 18'(ad_17) + 18'd1;
            bc_rnd <= 18'(bc_17) + 18'd1;
        end
    end

    wire signed [15:0] ac = ac_rnd[16:1]; // truncate
    wire signed [15:0] bd = bd_rnd[16:1];
    wire signed [15:0] ad = ad_rnd[16:1];
    wire signed [15:0] bc = bc_rnd[16:1];

    // ac-bd, ad+bc: CLK4
    logic signed [15:0] oddXtwi [0:1];
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            oddXtwi[0] <= '0;
            oddXtwi[1] <= '0;
        end
        else if (i_en) begin
            oddXtwi[0] <= ac - bd;
            oddXtwi[1] <= ad + bc;
        end
    end

    // shift register even
    logic signed [15:0] shiftreg_even [2:0] [0:1];
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            for (int i=0; i<3; i++) begin
                for (int j=0; j<2; j++) begin
                    shiftreg_even[i][j] <= '0;
                end
            end
        end
        else if (i_en) begin
            for (int j=0; j<2; j++) begin
                shiftreg_even[0][j] <= even[j];
            end
            for (int i=1; i<3; i++) begin
                for (int j=0; j<2; j++) begin
                    shiftreg_even[i][j] <= shiftreg_even[i-1][j];
                end
            end
        end
    end

    // top = even + oddXtwi, btm = even - oddXtwi: CLK5
    logic signed [16:0] top [0:1];
    logic signed [16:0] btm [0:1];
    always_ff @(posedge i_clk) begin
        for (int i=0; i<2; i++) begin
            if (i_rst) begin
                top[i] <= '0;
                btm[i] <= '0;
            end
            else if (i_en) begin
                top[i] <= shiftreg_even[2][i] + oddXtwi[i]; // 16-bit adder
                btm[i] <= shiftreg_even[2][i] - oddXtwi[i];
            end
        end
    end

    assign o_top[0] = top[0][16:1]; // divide by 2 here to prevent bit growth
    assign o_top[1] = top[1][16:1];
    assign o_btm[0] = btm[0][16:1];
    assign o_btm[1] = btm[1][16:1];

endmodule
