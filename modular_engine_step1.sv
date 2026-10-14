//=============================================================================
// 모듈러 연산 엔진 - 스텝 1 (SystemVerilog 버전)
//- MU_16 모듈 13개 인스턴스 포함
//- 입출력 포트를 2차원 배열(2D array)로 선언
//=============================================================================
module modular_engine_step1 #(
    parameter int WORD_WIDTH = 60 // 데이터 비트 폭 파라미터
)(
    input  logic                          clk,      // 공통 클럭
    input  logic                          rst_n,    // 공통 리셋 (active low)

    // --- 13x16 유닛을 위한 Control & Data Inputs (2D 배열) ---
    // 13개의 MU_16 모듈 각각에 16개의 입력이 전달됩니다.
    input  logic                          valid_in_arr [13][16],
    input  logic                          s_in_arr     [13][16],
    input  logic [2:0]                    mode_arr     [13][16],
    input  logic [WORD_WIDTH-1:0]         A_arr        [13][16],
    input  logic [WORD_WIDTH-1:0]         B_arr        [13][16],
    input  logic [WORD_WIDTH-1:0]         q_arr        [13][16],
    input  logic [2*WORD_WIDTH-1:0]       mu_arr       [13][16],
    input  logic [5:0]                    q_width_arr  [13][16],

    // --- 13x16 유닛의 Control & Data Outputs (2D 배열) ---
    output logic                          valid_out_arr[13][16],
    output logic [WORD_WIDTH-1:0]         result_arr   [13][16]
);

    //-------------------------------------------------------------------------
    // 13개의 MU_16 인스턴스 생성
    //-------------------------------------------------------------------------
    generate
        for (genvar j = 0; j < 13; j++) begin : gen_engine_instance
            MU_16 #(
                .WORD_WIDTH(WORD_WIDTH)
            ) u_MU_16_inst (
                .clk          (clk),
                .rst_n        (rst_n),

                // 2차원 배열의 첫 번째 인덱스(j)를 사용하여 각 MU_16에 1차원 배열을 전달
                .valid_in_arr (valid_in_arr[j]),
                .s_in_arr     (s_in_arr[j]),
                .mode_arr     (mode_arr[j]),
                .A_arr        (A_arr[j]),
                .B_arr        (B_arr[j]),
                .q_arr        (q_arr[j]),
                .mu_arr       (mu_arr[j]),
                .q_width_arr  (q_width_arr[j]),

                .valid_out_arr(valid_out_arr[j]),
                .result_arr   (result_arr[j])
            );
        end
    endgenerate

endmodule

//=============================================================================
// 16개의 모듈러 연산 유닛 (SystemVerilog 버전)
//- modular_unit 16개 인스턴스 포함
//- 입출력 포트를 배열(array)로 선언
//=============================================================================
module MU_16 #(
    parameter int WORD_WIDTH = 60 // 데이터 비트 폭 파라미터
)(
    input  logic                          clk,      // 공통 클럭
    input  logic                          rst_n,    // 공통 리셋 (active low)

    // --- 16개 유닛을 위한 Control & Data Inputs (배열 타입) ---
    input  logic                          valid_in_arr [16], // 입력 유효 신호 배열
    input  logic                          s_in_arr     [16], // s_in 신호 배열
    input  logic [2:0]                    mode_arr     [16], // 연산 모드 배열
    input  logic [WORD_WIDTH-1:0]         A_arr        [16], // 피연산자 A 배열
    input  logic [WORD_WIDTH-1:0]         B_arr        [16], // 피연산자 B 배열
    input  logic [WORD_WIDTH-1:0]         q_arr        [16], // 모듈러스 q 배열
    input  logic [2*WORD_WIDTH-1:0]       mu_arr       [16], // Barrett 곱셈용 상수 mu 배열
    input  logic [5:0]                    q_width_arr  [16], // q_width 배열

    // --- 16개 유닛의 Control & Data Outputs (배열 타입) ---
    output logic                          valid_out_arr[16], // 출력 유효 신호 배열
    output logic [WORD_WIDTH-1:0]         result_arr   [16]  // 연산 결과 배열
);

    //-------------------------------------------------------------------------
    // 16개의 modular_unit 인스턴스 생성
    //-------------------------------------------------------------------------
    // SystemVerilog에서는 genvar를 선언하지 않아도 for-loop에서 인덱스 변수(i)를 바로 선언하여 사용할 수 있습니다.
    generate
        for (genvar i = 0; i < 16; i++) begin : gen_mu_instance
            modular_unit #(
                .WORD_WIDTH(WORD_WIDTH)
            ) u_modular_unit_inst (
                .clk        (clk),
                .rst_n      (rst_n),
                
                // 각 인스턴스에 배열의 인덱스로 직접 연결
                .valid_in   (valid_in_arr[i]),
                .s_in       (s_in_arr[i]),
                .mode       (mode_arr[i]),
                .A          (A_arr[i]),
                .B          (B_arr[i]),
                .q          (q_arr[i]),
                .mu         (mu_arr[i]),
                .q_width    (q_width_arr[i]),

                .valid_out  (valid_out_arr[i]),
                .result     (result_arr[i])
            );
        end
    endgenerate

endmodule