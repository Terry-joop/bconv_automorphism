module CU #(
    parameter DATA_WIDTH = 58,
    parameter MAX_LEVEL = 17
)(
    input clk,
    input rst_n,
    input en_step_1,
    input en_step_2,
    input [4:0] level,
    input [DATA_WIDTH-1:0] coeff,
    input [DATA_WIDTH-1:0] param,
    input [DATA_WIDTH-1:0] q_in,
    input [DATA_WIDTH-1:0] ratio_precomp,

    output reg valid_Bconv_out,
    output reg [DATA_WIDTH-1:0] CU_out
);

    reg [DATA_WIDTH-1:0] buffer [0:MAX_LEVEL - 1]; 
    reg [4:0] buffer_count_1, buffer_count_2;
    reg [DATA_WIDTH-1:0] mux_out;
    wire [DATA_WIDTH-1:0] modadd;
    wire [DATA_WIDTH:0] temp_sum; 
    reg [DATA_WIDTH-1:0] cu_accum; 
    wire [DATA_WIDTH-1:0] modmult_out;
    wire mult_start, mult_done;
    reg en_step_1_d, en_step_1_dd;
    reg en_step_2_d, en_step_2_dd, en_step_2_ddd;

    assign mult_start = en_step_1 || en_step_2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en_step_1_d <= 0;
            en_step_1_dd <= 0;
            en_step_2_d <= 0;
            en_step_2_dd <= 0;
            en_step_2_ddd <= 0;
        end else begin
            en_step_1_d <= en_step_1;
            en_step_1_dd <= en_step_1_d;
            en_step_2_d <= en_step_2;
            en_step_2_dd <= en_step_2_d;
            en_step_2_ddd <= en_step_2_dd;
        end
    end

    always @(*) begin
        if (en_step_1) begin
            mux_out = coeff; 
        end else if (en_step_2) begin
            mux_out = buffer[buffer_count_2];
        end else begin
            mux_out = {DATA_WIDTH{1'b0}};
        end
    end

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < MAX_LEVEL; i = i + 1) begin
                buffer[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            if (mult_done && en_step_1_dd) begin
                buffer[buffer_count_1] <= modmult_out;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buffer_count_1 <= 0;
        end else begin
            if (en_step_1_dd)begin
                buffer_count_1 <= buffer_count_1 + 1;
            end
            if (buffer_count_1 >= level) begin
                buffer_count_1 <= 0; // Reset buffer count if it exceeds LEVEL
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buffer_count_2 <= 0;
        end else begin
            if (en_step_2 || en_step_2_dd)begin
                buffer_count_2 <= buffer_count_2 + 1;
            end else begin 
                buffer_count_2 <= 0;
            end
            if (buffer_count_2 >= level) begin
                buffer_count_2 <= 0; // Reset buffer count if it exceeds LEVEL
            end
        end
    end

    shoup_mult #(
        .WORD_WIDTH(DATA_WIDTH),
        .K_WIDTH(DATA_WIDTH)
    ) shoup (
        .clk        (clk),
        .rst_n      (rst_n),

        .valid_in   (mult_start),
        .a          (mux_out),
        .ratio      (param),
        .z_pre      (ratio_precomp),
        .q          (q_in),

        .valid_out  (mult_done),
        .result     (modmult_out)
    );

    reg [DATA_WIDTH-1:0] q_in_d, q_in_dd;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_in_d <= 0;
            q_in_dd <= 0;
        end else begin
            q_in_d <= q_in;
            q_in_dd <= q_in_d;
        end
    end

    assign temp_sum = en_step_2_dd ? 
                      ((buffer_count_2==4'd2) ? modmult_out : modmult_out + cu_accum)
                      : 0;

    assign modadd = (mult_done && (en_step_2_dd)) ?
                    ((temp_sum >= q_in_dd) ? (temp_sum - q_in_dd) : temp_sum[DATA_WIDTH-1:0]) : {DATA_WIDTH{1'b0}};

    // 누적 연산 (순차 논리)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cu_accum <= {DATA_WIDTH{1'b0}}; // 리셋 시 0으로 초기화
        end else begin
            if (mult_done && (en_step_2_dd)) begin
                cu_accum <= modadd;
            end 
        end
    end

    always @(buffer_count_2) begin
        if ((en_step_2_ddd) && (buffer_count_2 == 4'd2)) begin
            CU_out = cu_accum;
            valid_Bconv_out = 1;
        end else begin
            CU_out = {DATA_WIDTH{1'b0}};
            valid_Bconv_out = 0;
        end
    end


endmodule








