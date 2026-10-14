/*******************************************************************************
 * Module: VariableInputModularAdderTree
 * Description: 5~13개의 입력을 modular_add 모듈을 사용하여 파이프라인 구조로
 * 더하는 애더 트리. 총 4 사이클의 Latency를 가짐.
 ******************************************************************************/
module adder_tree #(
    parameter WIDTH = 60,
    parameter MAX_INPUTS = 13
) (
    input logic clk,
    input logic rst_n,

    input logic                  i_valid,
    input logic [WIDTH-1:0]      i_inputs [MAX_INPUTS-1:0],
    input logic [3:0]            i_input_count,
    input logic [WIDTH-1:0]      i_q,

    output logic                 o_valid,
    output logic [WIDTH-1:0]     o_sum
);

    // --- 스테이지 0: 입력 MUX (조합 논리) ---
    // i_input_count에 따라 사용하지 않는 입력을 0으로 만듦
    logic [WIDTH-1:0] muxed_inputs [MAX_INPUTS-1:0];
    always_comb begin
        for (int i = 0; i < MAX_INPUTS; i++) begin
            muxed_inputs[i] = (i < i_input_count) ? i_inputs[i] : '0;
        end
    end

    // --- 파이프라인 스테이지 1 (13 입력 -> 7 결과) ---
    logic [WIDTH-1:0] s1_results [6:0]; // 스테이지 1의 결과 (다음 스테이지의 입력)
    logic             valid_s1;         // 스테이지 1의 유효 신호

    generate
        // 6개의 modular_add 인스턴스 생성
        for (genvar i = 0; i < 6; i++) begin : S1_ADDERS
            modular_add #(.WORD_WIDTH(WIDTH)) u_s1_add (
                .clk(clk), 
                .rst_n(rst_n),
                .valid_in(i_valid),
                .A(muxed_inputs[i*2]),
                .B(muxed_inputs[i*2 + 1]),
                .q(i_q),
                .result(s1_results[i]),
                .valid_out() // 중간 valid는 사용하지 않음
            );
        end
    endgenerate

    // 남은 1개의 입력(muxed_inputs[12])과 valid 신호를 다음 스테이지로 전달하기 위해 레지스터에 저장
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_results[6] <= '0;
            valid_s1      <= 1'b0;
        end else begin
            s1_results[6] <= muxed_inputs[12];
            valid_s1      <= i_valid;
        end
    end

    // --- 파이프라인 스테이지 2 (7 입력 -> 4 결과) ---
    logic [WIDTH-1:0] s2_results [3:0];
    logic             valid_s2;

    generate
        // 3개의 modular_add 인스턴스 생성
        for (genvar i = 0; i < 3; i++) begin : S2_ADDERS
            modular_add #(.WORD_WIDTH(WIDTH)) u_s2_add (
                .clk(clk), 
                .rst_n(rst_n),
                .valid_in(valid_s1),
                .A(s1_results[i*2]),
                .B(s1_results[i*2 + 1]),
                .q(i_q),
                .result(s2_results[i]),
                .valid_out()
            );
        end
    endgenerate

    // 남은 1개의 입력(s1_results[6])과 valid 신호를 레지스터에 저장
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_results[3] <= '0;
            valid_s2      <= 1'b0;
        end else begin
            s2_results[3] <= s1_results[6];
            valid_s2      <= valid_s1;
        end
    end

    // --- 파이프라인 스테이지 3 (4 입력 -> 2 결과) ---
    logic [WIDTH-1:0] s3_results [1:0];
    logic             valid_s3;

    generate
        // 2개의 modular_add 인스턴스 생성
        for (genvar i = 0; i < 2; i++) begin : S3_ADDERS
            modular_add #(.WORD_WIDTH(WIDTH)) u_s3_add (
                .clk(clk), 
                .rst_n(rst_n),
                .valid_in(valid_s2),
                .A(s2_results[i*2]),
                .B(s2_results[i*2 + 1]),
                .q(i_q),
                .result(s3_results[i]),
                .valid_out()
            );
        end
    endgenerate

    // valid 신호를 레지스터에 저장
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s3 <= 1'b0;
        end else begin
            valid_s3 <= valid_s2;
        end
    end

    // --- 파이프라인 스테이지 4 (2 입력 -> 1 최종 결과) ---
    // 마지막 스테이지는 모듈의 최종 출력으로 직접 연결됨
    modular_add #(.WORD_WIDTH(WIDTH)) u_final_add (
        .clk(clk), 
        .rst_n(rst_n),
        .valid_in(valid_s3),
        .A(s3_results[0]),
        .B(s3_results[1]),
        .q(i_q),
        .result(o_sum),      // 최종 결과 출력
        .valid_out(o_valid)  // 최종 유효 신호 출력
    );

endmodule


//=============================================================================
// 13개의 애더 트리 (SystemVerilog 버전)
//- adder_tree 모듈 13개 인스턴스 포함
//- 입출력 포트를 배열로 선언
//=============================================================================
module adder_tree_13 #(
    parameter int WIDTH = 60,
    parameter int MAX_INPUTS = 13
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // --- 13개 애더 트리를 위한 Control & Data Inputs (배열) ---
    input  logic                          i_valid_arr       [13],
    input  logic [WIDTH-1:0]              i_inputs_arr      [13][MAX_INPUTS-1:0],
    input  logic [3:0]                    i_input_count_arr [13],
    input  logic [WIDTH-1:0]              i_q_arr           [13],

    // --- 13개 애더 트리의 Control & Data Outputs (배열) ---
    output logic                          o_valid_arr       [13],
    output logic [WIDTH-1:0]              o_sum_arr         [13]
);

    //-------------------------------------------------------------------------
    // 13개의 adder_tree 인스턴스 생성
    //-------------------------------------------------------------------------
    generate
        for (genvar i = 0; i < 13; i++) begin : gen_adder_tree_instance
            adder_tree #(
                .WIDTH(WIDTH),
                .MAX_INPUTS(MAX_INPUTS)
            ) u_adder_tree_inst (
                .clk             (clk),
                .rst_n           (rst_n),
                
                // 각 인스턴스에 배열의 인덱스로 직접 연결
                .i_valid         (i_valid_arr[i]),
                .i_inputs        (i_inputs_arr[i]),
                .i_input_count   (i_input_count_arr[i]),
                .i_q             (i_q_arr[i]),
                
                .o_valid         (o_valid_arr[i]),
                .o_sum           (o_sum_arr[i])
            );
        end
    endgenerate

endmodule