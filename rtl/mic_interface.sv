`timescale 1ns / 1ps

/*

*/

module mic_interface(
    input i_clk100MHz, // 100 MHz
    input i_rst,
    input i_en,
    input i_mic_data,
    output o_mic_clk,
    output o_mic_lrsel,
    output [7:0] o_amplitude,
    output o_valid
    );

    // mic clock
    logic [4:0] mic_clk_counter;
    wire mic_clk;

    always_ff @(posedge i_clk100MHz) begin
        if (i_rst) begin
            mic_clk_counter <= '0;
        end
        else if (i_en) begin
            mic_clk_counter <= mic_clk_counter + 1;
        end
    end

    assign mic_clk = mic_clk_counter[4]; // 100 MHz / 32 = ~3 MHz

    assign o_mic_clk = mic_clk;

    // rising edge of mic clk
    logic mic_clk_prev;

    always_ff @(posedge i_clk100MHz) begin
        mic_clk_prev <= mic_clk;
    end

    wire mic_clk_rising_edge = mic_clk & ~mic_clk_prev; 

    // double flop asynchronous mic data
    logic mic_data_ff1, mic_data_ff2;

    always_ff @(posedge i_clk100MHz) begin
        mic_data_ff1 <= i_mic_data;  
        mic_data_ff2 <= mic_data_ff1; 
    end

    // sliding window shift register
    parameter AMPLITUDE_SIZE = 8;
    parameter PDM_WINDOW_LENGTH = 2**AMPLITUDE_SIZE; // 256
    logic [PDM_WINDOW_LENGTH-1:0] sliding_window;
    logic [AMPLITUDE_SIZE-1:0] pdm_sum;

    always_ff @(posedge i_clk100MHz) begin
        if (i_rst) begin
            sliding_window <= '0;
            pdm_sum <= '0;
        end
        else if (i_en && mic_clk_rising_edge) begin
            sliding_window <= {sliding_window[PDM_WINDOW_LENGTH-2:0], mic_data_ff2};

            if ((sliding_window[PDM_WINDOW_LENGTH-1] == 1'b1) && (mic_data_ff2 == 1'b0)) begin
                pdm_sum <= pdm_sum - 1;
            end
            else if ((sliding_window[PDM_WINDOW_LENGTH-1] == 1'b0) && (mic_data_ff2 == 1'b1)) begin
                pdm_sum <= pdm_sum + 1;
            end
        end
    end

    // sample ampltitude
    logic [6:0] sample_rate_counter;
    logic [AMPLITUDE_SIZE-1:0] amplitude;
    logic valid;
    
    always_ff @(posedge i_clk100MHz) begin
        if (i_rst) begin
            sample_rate_counter <= '0;
            amplitude <= '0;
            valid <= 1'b0;
        end
        else if (i_en && mic_clk_rising_edge) begin
            if (sample_rate_counter == 7'd127) begin
                sample_rate_counter <= '0;
                amplitude <= pdm_sum; // updates @ 100 MHz / 2^12 = ~ 24.44 kHz
                valid <= 1'b1;
            end
            else begin
                sample_rate_counter <= sample_rate_counter + 1;
                valid <= 1'b0;
            end
        end
        else begin
            valid <= 1'b0;
        end
    end

    assign o_amplitude = amplitude;
    assign o_valid = valid;

    assign o_mic_lrsel = 1'b0;

endmodule
