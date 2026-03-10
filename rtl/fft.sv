`timescale 1ns / 1ps

// no memory load implemented yet, that is a later step. for now, assume data is already loaded in memory

module fft(
    input i_clk,
    input i_rst,
    input i_en,
    input i_start_fft,
    input i_start_graph,
    output o_busy,
    output o_hs,
    output o_vs,
    output o_g0
    );

    // - - - Control - - -
    wire [9:0] even_addr;
    wire [9:0] odd_addr;
    wire [8:0] twi_addr;
    wire [9:0] top_addr;
    wire [9:0] btm_addr;
    wire rd_mem0;
    wire rd_mem1;
    wire wr_mem0;
    wire wr_mem1;
    wire en_graph;

    control control0 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_en(i_en),
        .i_start_fft(i_start_fft),
        .i_start_graph(i_start_graph),
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
        .o_en_graph(en_graph)
    );



    // - - - Shift registers - - - 
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



    // - - - Memory - - - 

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

    // - - data RAM - - 

    // mux addresses
    wire [9:0] addr0 [0:1]; // address for mem0; port A and port B
    wire [9:0] addr1 [0:1];
    wire [9:0] grapher_addr;

    assign addr0[0] = en_graph ? grapher_addr : (wr_mem0_reg[PIPELINE_DEPTH] ? top_addr_reg[PIPELINE_DEPTH] : even_addr);
    assign addr0[1] = wr_mem0_reg[PIPELINE_DEPTH] ? btm_addr_reg[PIPELINE_DEPTH] : odd_addr;
    assign addr1[0] = wr_mem1_reg[PIPELINE_DEPTH] ? top_addr_reg[PIPELINE_DEPTH] : even_addr;
    assign addr1[1] = wr_mem1_reg[PIPELINE_DEPTH] ? btm_addr_reg[PIPELINE_DEPTH] : odd_addr;

    // pack write data
    wire [31:0] wr_data [0:1];
    wire signed [15:0] top [0:1];
    wire signed [15:0] btm [0:1];

    assign wr_data[0] = {top[1], top[0]}; // port 0 is top; port 1 is btm
    assign wr_data[1] = {btm[1], btm[0]}; // [15:0] real part; [31:16] imag part

    // write enables
    logic [1:0] wr_en0;
    logic [1:0] wr_en1;

    assign wr_en0 = {2{wr_mem0_reg[PIPELINE_DEPTH]}}; 
    assign wr_en1 = {2{wr_mem1_reg[PIPELINE_DEPTH]}};

    wire [31:0] rd_data0 [0:1];
    wire [31:0] rd_data1 [0:1];

    bram #(.MEM_FILE("input_signal.mem")) mem0 (
        .i_clk(i_clk),
        .i_wr_en(wr_en0),
        .i_addr(addr0),
        .i_wr_data(wr_data),
        .o_rd_data(rd_data0)
    );
    bram mem1 (
        .i_clk(i_clk),
        .i_wr_en(wr_en1),
        .i_addr(addr1),
        .i_wr_data(wr_data),
        .o_rd_data(rd_data1)
    );



    // - - - Butterfly - - -

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

    // clock domain crossing

    grapher grapher0 (
    .i_vga_clk(i_clk),
    .i_rst(i_rst),
    .i_en(en_graph),
    .i_rd_data(rd_data0[0]), // mem0 port 0
    .o_rd_addr(grapher_addr),
    .o_hs(o_hs),
    .o_vs(o_vs),
    .o_g0(o_g0)
    );

endmodule
