`timescale 1ns / 1ps



module control(
    input i_clk,
    input i_rst,
    input i_en,
    input i_start_fft,
    input i_start_graph,
    output [9:0] o_even_addr,
    output [9:0] o_odd_addr,
    output [8:0] o_twi_addr,
    output [9:0] o_top_addr,
    output [9:0] o_btm_addr,
    output o_rd_mem0,
    output o_rd_mem1,
    output o_wr_mem0,
    output o_wr_mem1,
    output o_busy,
    output o_en_graph
    );

    // state machine: CLK1

    typedef enum logic [1:0] {
        IDLE,
        ACTIVE,
        STALL,
        GRAPH
    } state_t;

    state_t state = IDLE;
    logic [3:0] stage_counter = '0;
    logic [8:0] pair_counter  = '0;
    logic [2:0] stall_counter = '0;

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            state         <= IDLE;
            stage_counter <= '0;
            pair_counter  <= '0;
            stall_counter <= '0;
            
        end
        else if (i_en) begin
            case (state)

                IDLE: begin
                    if (i_start_fft) begin // IDLE -> ACTIVE state transition
                        state         <= ACTIVE;
                        stage_counter <= '0;
                        pair_counter  <= '0;
                    end
                    else if (i_start_graph) begin
                        state <= GRAPH;
                    end
                end

                GRAPH: begin
                    if (i_start_fft) begin // GRAPH -> ACTIVE state transition
                        state         <= ACTIVE;
                        stage_counter <= '0;
                        pair_counter  <= '0;
                    end
                end

                ACTIVE: begin
                    if (pair_counter == 9'd511) begin // ACTIVE -> STALL state transition
                        stall_counter <= 3'd6;   // load countdown
                        state         <= STALL;
                    end
                    else begin
                        pair_counter <= pair_counter + 1;
                    end
                end

                STALL: begin
                    if (stall_counter == '0) begin
                        if (stage_counter == 4'd9) begin // STALL -> IDLE state transition
                            state         <= IDLE;
                        end
                        else begin // STALL -> ACTIVE state transition
                            stage_counter <= stage_counter + 1;
                            state         <= ACTIVE;
                            pair_counter  <= 0;
                        end
                    end
                    else begin
                        stall_counter <= stall_counter - 1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign o_busy = (state != IDLE);

    // generate addresses: CLK2
    logic [9:0] even_addr;
    logic [9:0] odd_addr;
    logic [8:0] twi_addr;
    logic [9:0] top_addr;
    logic [9:0] btm_addr;
    logic rd_mem0;
    logic rd_mem1;
    logic wr_mem0;
    logic wr_mem1;
    wire [9:0] index_2n = pair_counter << 1;
    wire [9:0] index_2n1 = (pair_counter << 1) + 1;
    wire [8:0] within_group;
    wire [8:0] group_idx;

    assign group_idx    = pair_counter >> stage_counter;
    assign within_group = pair_counter & ((10'd1 << stage_counter) - 1);

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            even_addr <= '0;
            odd_addr <= '0;
            twi_addr <= '0;
            top_addr <= '0;
            btm_addr <= '0;
            rd_mem0 <= 0;
            rd_mem1 <= 0;
            wr_mem0 <= 0;
            wr_mem1 <= 0;
        end
        else if (i_en) begin
            if (state == ACTIVE) begin
                rd_mem0 <= !stage_counter[0];
                rd_mem1 <= stage_counter[0];
                wr_mem0 <= stage_counter[0];
                wr_mem1 <= !stage_counter[0];

                if (stage_counter == 4'd0) begin
                    for (int i=0; i<10; i++) begin
                        even_addr[i] <= index_2n[9-i]; // bit reverse
                        odd_addr[i] <= index_2n1[9-i];
                    end
                    twi_addr <= '0;
                    top_addr <= index_2n;
                    btm_addr <= index_2n1;
                end
                else begin
                    even_addr <= (group_idx << (stage_counter + 1)) | within_group;
                    odd_addr  <= ((group_idx << (stage_counter + 1)) | within_group) | (10'd1 << stage_counter);
                    twi_addr <= within_group << (9 - stage_counter);
                    top_addr <= (group_idx << (stage_counter + 1)) | within_group;
                    btm_addr <= ((group_idx << (stage_counter + 1)) | within_group) | (10'd1 << stage_counter);
                end
            end
            else begin
                wr_mem0 <= 0;
                wr_mem1 <= 0;
            end
        end
    end

    assign o_even_addr = even_addr;
    assign o_odd_addr = odd_addr;
    assign o_twi_addr = twi_addr;
    assign o_top_addr = top_addr;
    assign o_btm_addr = btm_addr;
    assign o_rd_mem0 = rd_mem0;
    assign o_rd_mem1 = rd_mem1;
    assign o_wr_mem0 = wr_mem0;
    assign o_wr_mem1 = wr_mem1;

    assign o_en_graph = (state == GRAPH);

endmodule
