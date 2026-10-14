module Bconv #(
    parameter DATA_WIDTH = 58,
    parameter NUM_CU = 16 
)(
    input clk,
    input rst_n,
    input start_Bconv,
    input [4:0] level_in,
    input [4:0] level_out,

    input [NUM_CU-1:0][DATA_WIDTH-1:0] coeff,
    input [NUM_CU-1:0][DATA_WIDTH-1:0] param,
    input [NUM_CU-1:0][DATA_WIDTH-1:0] q_in,
    input [NUM_CU-1:0][DATA_WIDTH-1:0] ratio_precomp,

    output [NUM_CU-1:0] valid_Bconv_out,
    output [NUM_CU-1:0][DATA_WIDTH-1:0] CU_out
); 	

    parameter IDLE 	= 2'b00; 
    parameter STEP1 = 2'b01; 
    parameter STEP2 = 2'b10; 

    reg [1:0] current_state, next_state;

    reg [4:0] counter_1, counter_2, counter_3;
    
    wire en_step_1, en_step_2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter_1 <= 0;
            counter_2 <= 0;
            counter_3 <= 0;
        end else begin
            if (current_state == IDLE) begin
                counter_1 <= 0; 
                counter_2 <= 0;
                counter_3 <= 0;
            end else if (current_state == STEP1) begin
                counter_1 <= counter_1 + 1;
                counter_2 <= 0;
                counter_3 <= 0;
            end else if (current_state == STEP2) begin
                counter_1 <= 0; 
                if (counter_2 == level_in) begin
                    counter_2 <= 0;
                end else begin
                    counter_2 <= counter_2 + 1;
                end
                if (counter_2 == level_in) begin
                    counter_3 <= counter_3 + 1;
                end
            end
        end
    end


    always @(*) begin
        case (current_state)
            IDLE: begin
                if (start_Bconv)
                    next_state = STEP1; 
                else
                    next_state = IDLE; 	
            end
            STEP1: begin
                if (counter_1 == level_in)
                    next_state = STEP2;
                else
                    next_state = STEP1;
            end
            STEP2: begin
                if (start_Bconv) 
                    next_state = STEP1; 
                else if ((counter_2 == level_in) && (counter_3 == (level_out - 1'd1)))
                    next_state = IDLE;
                else
                    next_state = STEP2;
            end
            default: begin
                next_state = IDLE; 
            end
        endcase
    end

    assign en_step_1 = (current_state == STEP1) ? 1'b1 : 1'b0;
    assign en_step_2 = (current_state == STEP2) ? 1'b1 : 1'b0;

    genvar i;
    generate
        for (i = 0; i < NUM_CU; i = i + 1) begin : CU_inst_loop
            CU #(
                .DATA_WIDTH(DATA_WIDTH),
                .MAX_LEVEL(17)
            ) CU_inst (
                .clk(clk),
                .rst_n(rst_n),
                .en_step_1(en_step_1),
                .en_step_2(en_step_2),
                .level(level_in),
                
                .coeff(coeff[i]),
                .param(param[i]),
                .q_in(q_in[i]),
                .ratio_precomp(ratio_precomp[i]),
                
                .valid_Bconv_out(valid_Bconv_out[i]),
                .CU_out(CU_out[i])
            );
        end
    endgenerate
    
endmodule




