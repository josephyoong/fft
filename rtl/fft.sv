`timescale 1ns / 1ps

/*



*/

module fft(
    input i_clk,
    input i_clk_25MHz,
    input i_rst,
    input i_en,
    input i_start_fft,
    input i_start_graph,
    input i_load,
    input i_mic_data,
    output o_busy,
    output o_hs,
    output o_vs,
    output logic o_g0,
    output o_mic_clk,
    output o_lrsel
    );

    // vga
    wire hs;
    wire vs;
    wire active_video;
    wire [9:0] x_pos;
    wire [8:0] y_pos;

    vga vga0 (
        .i_clk_25MHz(i_clk_25MHz),
        .o_hs(hs),
        .o_vs(vs),
        .o_active_video(active_video),
        .o_x_pos(x_pos),
        .o_y_pos(y_pos)
    );

    // mic interface
    /*
    amplitude sampled every 4096 periods of clk 100 MHz => ~24.4 kHz sampling frequency
    valid pulses high for 1 clk cycle when amplitude is updated
    */
    wire [7:0] amplitude;
    wire valid;

    mic_interface mic_interface0 (
        .i_clk100MHz(i_clk),
        .i_rst(i_rst),
        .i_en(i_en),
        .i_mic_data(i_mic_data),
        .o_mic_clk(o_mic_clk),
        .o_mic_lrsel(o_lrsel),
        .o_amplitude(amplitude),
        .o_valid(valid)
    );

    // write amplitude to memory
    /*
    wr ptr increments with every amplitude sample making memory a circular buffer

    memory depth depends on how much of the signal you want to store 
    how much of the signal you want to store depends on the size of your graph
    */
    parameter DEPTH = 1024;
    logic [$clog2(DEPTH)-1:0] wr_ptr;

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            wr_ptr <= '0;
        end
        else if (i_en && valid) begin
            wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1;
        end
    end

    wire [7:0] amp;
    wire [7:0] unconnected;
    logic [$clog2(DEPTH)-1:0] rd_ptr;

    bram #(.WIDTH(8), .DEPTH(DEPTH)) circular_buffer (
        // port 0: write 
        .i_clk_0(i_clk),
        .i_wr_en_0(valid),
        .i_addr_0(wr_ptr),
        .i_wr_data_0(amplitude),
        .o_rd_data_0(unconnected),
        // port 1: vga read
        .i_clk_1(i_clk_25MHz),
        .i_wr_en_1(1'b0),
        .i_addr_1(rd_ptr),
        .i_wr_data_1(8'd0),
        .o_rd_data_1(amp)
    );

    // read amplitude from memory
    /*
    clock domain crossing
    wr ptr (i_clk 100 MHz) -> wr ptr (vga_clk ~25 MHz)
    convert to gray code
    even though wr ptr is in 100 MHz clock domain, it only updates @ ~24.4 KHz,
    so the ~25 MHz clock domain can sample it by double flopping
    the slow ~25 MHz clock will not miss a change in wr ptr
    */
    // binary to gray (100 MHz)
    wire [$clog2(DEPTH)-1:0] wr_ptr_gray;

    assign wr_ptr_gray = wr_ptr ^ (wr_ptr >> 1);

    // double flop (25 MHz)
    logic [$clog2(DEPTH)-1:0] wr_ptr_gray_ff1, wr_ptr_gray_ff2;

    always_ff @(posedge i_clk_25MHz) begin
        wr_ptr_gray_ff1 <= wr_ptr_gray;
        wr_ptr_gray_ff2 <= wr_ptr_gray_ff1;
    end

    // gray to binary (25 MHz)
    logic [$clog2(DEPTH)-1:0] wr_ptr_vga;

    always_comb begin
        wr_ptr_vga[$clog2(DEPTH)-1] = wr_ptr_gray_ff2[$clog2(DEPTH)-1];
        for (int i=$clog2(DEPTH)-2; i>=0; i--) begin
            wr_ptr_vga[i] = wr_ptr_vga[i+1] ^ wr_ptr_gray_ff2[i];
        end
    end

    // input signal grapher
    parameter PADDING = 200;
    parameter X_START_GRAPH = 64;
    parameter GRAPH_WIDTH = 512;
    parameter X_END_GRAPH = X_START_GRAPH + GRAPH_WIDTH;
    parameter Y_START_GRAPH = 0;
    parameter GRAPH_HEIGHT = 256;
    parameter Y_END_GRAPH = Y_START_GRAPH + GRAPH_HEIGHT;

    logic [8:0] x_pos_graph;
    logic [7:0] y_pos_graph;
    logic active_graph;
    
    always_comb begin
        if ((active_video) && 
            (x_pos >= X_START_GRAPH) && (x_pos < X_END_GRAPH) &&
            (y_pos >= Y_START_GRAPH) && (y_pos < Y_END_GRAPH)) begin

            x_pos_graph = x_pos - X_START_GRAPH;
            y_pos_graph = y_pos - Y_START_GRAPH;

            active_graph = 1;
        end
        else begin
            x_pos_graph = '0;
            y_pos_graph = '0;

            active_graph = 0;
        end
    end

    logic r_active_graph;
    logic [$clog2(DEPTH)-1:0] start_rd_ptr;
    logic [7:0] r_y_pos_graph;

    // set rd ptr at the start each y line on the graph
    always_ff @(posedge i_clk_25MHz) begin
        r_active_graph <= active_graph;
        r_y_pos_graph <= y_pos_graph;

        if ((x_pos == 10'd0) && (y_pos == Y_START_GRAPH)) begin
            start_rd_ptr <= wr_ptr_vga + PADDING;
        end
        else if (x_pos == X_START_GRAPH - 1) begin
            rd_ptr <= start_rd_ptr;
        end
        else begin
            rd_ptr <= rd_ptr + 1;
        end
    end

    logic draw_input_signal;

    // compare
    always_ff @(posedge i_clk_25MHz) begin
        if (r_active_graph) begin
            draw_input_signal <= (amp == r_y_pos_graph) ? 1 : 0;
        end
        else begin
            draw_input_signal <= 0;
        end
    end

    logic [2:0] r_hs;
    logic [2:0] r_vs;
    logic [1:0] r_draw_input_signal;

    // delay hs and vs
    /*
    time signal grapher needs 1 clk delay
    fft signal grapher needs 2 clk delay
    1 more clk delay to reg o_g0 because of combination OR of time signal draw with fft spectrum draw
    */
    always_ff @(posedge i_clk_25MHz) begin
        r_draw_input_signal[0] <= draw_input_signal; // needs 1 clk delay since has to wait for fft grapher 
        r_draw_input_signal[1] <= r_draw_input_signal[0];

        r_hs[0] <= hs;
        r_vs[0] <= vs;
        r_hs[1] <= r_hs[0];
        r_vs[1] <= r_vs[0];
        r_hs[2] <= r_hs[1];
        r_vs[2] <= r_vs[1];
    end

    assign o_hs = r_hs[2];
    assign o_vs = r_vs[2];

    // cdc load signal

    (* ASYNC_REG = "TRUE" *) logic [1:0] load_sync;

    always_ff @(posedge i_clk) begin
        load_sync[0] <= i_load;
        load_sync[1] <= load_sync[0];
    end

    // control
    wire [9:0] even_addr;
    wire [9:0] odd_addr;
    wire [8:0] twi_addr;
    wire [9:0] top_addr;
    wire [9:0] btm_addr;
    wire rd_mem0;
    wire rd_mem1;
    wire wr_mem0;
    wire wr_mem1;
    wire en_copy;
    wire [9:0] load_counter;
    wire en_load;
    wire [9:0] copy_counter;

    control control0 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_en(i_en),
        .i_start_fft(i_start_fft),
        .i_start_graph(i_start_graph),
        .i_load(load_sync[1]),
        .i_valid(valid),
        .o_even_addr(even_addr),
        .o_odd_addr(odd_addr),
        .o_twi_addr(twi_addr),
        .o_top_addr(top_addr),
        .o_btm_addr(btm_addr),
        .o_rd_mem0(rd_mem0),
        .o_rd_mem1(rd_mem1),
        .o_wr_mem0(wr_mem0),
        .o_wr_mem1(wr_mem1),
        .o_busy(o_busy),
        .o_en_copy(en_copy),
        .o_load_counter(load_counter),
        .o_en_load(en_load),
        .o_copy_counter(copy_counter)
    );



    // shift registers
    parameter PIPELINE_DEPTH = 5;
    logic shiftreg_rd_mem0;
    logic [PIPELINE_DEPTH:0] wr_mem0_reg;
    logic [PIPELINE_DEPTH:0] wr_mem1_reg;
    logic [9:0] top_addr_reg [0:PIPELINE_DEPTH];
    logic [9:0] btm_addr_reg [0:PIPELINE_DEPTH];

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            shiftreg_rd_mem0 <= 0;
            wr_mem0_reg <= '0;
            wr_mem1_reg <= '0;

            for (int i=0; i<6; i++) begin
                top_addr_reg[i] <= '0;
                btm_addr_reg[i] <= '0;
            end
        end
        else if (i_en) begin
            shiftreg_rd_mem0 <= rd_mem0; // CLK1

            wr_mem0_reg[0] <= wr_mem0;
            wr_mem1_reg[0] <= wr_mem1;
            top_addr_reg[0] <= top_addr;
            btm_addr_reg[0] <= btm_addr;

            for (int i=1; i<PIPELINE_DEPTH+1; i++) begin
                wr_mem0_reg[i] <= wr_mem0_reg[i-1];
                wr_mem1_reg[i] <= wr_mem1_reg[i-1];
                top_addr_reg[i] <= top_addr_reg[i-1];
                btm_addr_reg[i] <= btm_addr_reg[i-1];
            end
        end
    end



    // memory

    // - - twiddle factor ROM - - 
    wire [31:0] rom_data;

    rom rom0 (
        .i_clk(i_clk),
        .i_addr(twi_addr),
        .o_rd_data(rom_data)
    );

    wire signed [15:0] twi [0:1];
    assign twi[0] = rom_data[15:0];
    assign twi[1] = rom_data[31:16];

    // data bram

    // mux addresses
    wire [9:0] addr0 [0:1]; // address for mem0; port A and port B
    wire [9:0] addr1 [0:1];

    assign addr0[0] = en_copy ? copy_counter : (wr_mem0_reg[PIPELINE_DEPTH] ? top_addr_reg[PIPELINE_DEPTH] : even_addr);
    assign addr0[1] = en_load ? load_counter : (wr_mem0_reg[PIPELINE_DEPTH] ? btm_addr_reg[PIPELINE_DEPTH] : odd_addr);
    assign addr1[0] = wr_mem1_reg[PIPELINE_DEPTH] ? top_addr_reg[PIPELINE_DEPTH] : even_addr;
    assign addr1[1] = wr_mem1_reg[PIPELINE_DEPTH] ? btm_addr_reg[PIPELINE_DEPTH] : odd_addr;

    // pack write data
    wire [31:0] wr_data [0:1];
    wire signed [15:0] top [0:1];
    wire signed [15:0] btm [0:1];

    assign wr_data[0] = {top[1], top[0]}; // port 0 is top; port 1 is btm
    assign wr_data[1] = en_load ? {16'd0, {2'd0, amplitude, 6'd0}} : {btm[1], btm[0]}; // [15:0] real part; [31:16] imag part

    // write enables
    logic [1:0] wr_en0;
    logic [1:0] wr_en1;

    assign wr_en0[0] = wr_mem0_reg[PIPELINE_DEPTH]; 
    assign wr_en0[1] = en_load ? valid : wr_mem0_reg[PIPELINE_DEPTH]; 
    assign wr_en1[0] = wr_mem1_reg[PIPELINE_DEPTH];
    assign wr_en1[1] = wr_mem1_reg[PIPELINE_DEPTH];

    wire [31:0] rd_data0 [0:1];
    wire [31:0] rd_data1 [0:1];

    bram mem0 (
        // port 0: even or top
        .i_clk_0(i_clk),
        .i_wr_en_0(wr_en0[0]),
        .i_addr_0(addr0[0]),
        .i_wr_data_0(wr_data[0]),
        .o_rd_data_0(rd_data0[0]),
        // port 1: odd or btm
        .i_clk_1(i_clk),
        .i_wr_en_1(wr_en0[1]),
        .i_addr_1(addr0[1]),
        .i_wr_data_1(wr_data[1]),
        .o_rd_data_1(rd_data0[1])
    );

    bram mem1 (
        .i_clk_0(i_clk),
        .i_wr_en_0(wr_en1[0]),
        .i_addr_0(addr1[0]),
        .i_wr_data_0(wr_data[0]),
        .o_rd_data_0(rd_data1[0]),

        .i_clk_1(i_clk),
        .i_wr_en_1(wr_en1[1]),
        .i_addr_1(addr1[1]),
        .i_wr_data_1(wr_data[1]),
        .o_rd_data_1(rd_data1[1])
    );



    // butterfly

    // mux 
    wire signed [15:0] even [0:1];
    wire signed [15:0] odd [0:1];
    
    assign even[0] = shiftreg_rd_mem0 ? rd_data0[0][15:0] : rd_data1[0][15:0];
    assign even[1] = shiftreg_rd_mem0 ? rd_data0[0][31:16] : rd_data1[0][31:16];
    assign odd[0] = shiftreg_rd_mem0 ? rd_data0[1][15:0] : rd_data1[1][15:0];
    assign odd[1] = shiftreg_rd_mem0 ? rd_data0[1][31:16] : rd_data1[1][31:16];

    butterfly #(.I(1), .F(15)) butterfly0 (
        .i_clk(i_clk),
        .i_en(i_en),
        .i_rst(i_rst),
        .i_even(even),
        .i_odd(odd),
        .i_twi(twi),
        .o_top(top),
        .o_btm(btm)
    );



    // 
    logic r_en_copy;
    logic [9:0] r_copy_counter;

    always_ff @(posedge i_clk) begin
        r_en_copy <= en_copy;
        r_copy_counter <= copy_counter;
    end

    wire [31:0] unconnected1;
    wire [9:0] grapher_addr;
    wire [31:0] fft_result_data;

    bram mem2 (
        // copy fft result
        .i_clk_0(i_clk),
        .i_wr_en_0(r_en_copy),
        .i_addr_0(r_copy_counter),
        .i_wr_data_0(rd_data0[0]), //
        .o_rd_data_0(unconnected1), // not used
        // vga grapher
        .i_clk_1(i_clk_25MHz),
        .i_wr_en_1(1'b0),
        .i_addr_1(grapher_addr),
        .i_wr_data_1(32'd0), // not used
        .o_rd_data_1(fft_result_data)
    );

    // fft grapher 
    /*
    clock domain crossing
    this is a rough grapher; it reads data while its also being written to but its okay
    cdc fast domain to slow domain; is it ok to double flop? since i know rst will be slow
    */
    // double flop rst
    logic [1:0] rst_ff;

    always_ff @(posedge i_clk_25MHz) begin
        rst_ff[0] <= i_rst;
        rst_ff[1] <= rst_ff[0];
    end

    wire fft_draw;

    grapher grapher0 (
    .i_clk_25MHz(i_clk_25MHz),
    .i_rst(rst_ff[1]),
    .i_en(1'b1),
    .i_hs(hs),
    .i_vs(vs),
    .i_x_pos(x_pos),
    .i_y_pos(y_pos),
    .i_active_video(active_video),
    .i_rd_data(fft_result_data),
    .o_rd_addr(grapher_addr),
    .o_draw(fft_draw)
    );

    always_ff @(posedge i_clk_25MHz) begin
        o_g0 <= fft_draw | r_draw_input_signal[0];
    end

endmodule
