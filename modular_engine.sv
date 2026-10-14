//=============================================================================
// 모듈러 연산 엔진 (최상위 모듈) - 출력 경로 수정됨
// - adder_tree 출력을 위한 별도 포트 추가
// - step2 출력 경로를 Demux로 변경
//=============================================================================
module modular_engine #(
    parameter int WORD_WIDTH = 60,
    parameter int MAX_INPUTS = 13
)(
    input  logic                          clk,
    input  logic                          rst_n,

    // --- 1024 유닛을 위한 통합 입력 ---
    input  logic                          valid_in_arr [1024],
    input  logic                          s_in_arr     [1024],
    input  logic [2:0]                    mode_arr     [1024],
    input  logic [WORD_WIDTH-1:0]         A_arr        [1024],
    input  logic [WORD_WIDTH-1:0]         B_arr        [1024],
    input  logic [WORD_WIDTH-1:0]         q_arr        [1024],
    input  logic [2*WORD_WIDTH-1:0]       mu_arr       [1024],
    input  logic [5:0]                    q_width_arr  [1024],

    // --- 제어 신호 ---
    // step2_mode[i]가 1이면 i번째 step2 출력이 adder tree로 라우팅됨
    input  logic                          step2_mode [4],
    input  logic [3:0]                    adder_tree_input_count_arr [4][13],
    
    // --- 1024 유닛의 통합 출력 ---
    output logic                          valid_out_arr[1024],
    output logic [WORD_WIDTH-1:0]         result_arr   [1024],

    // --- Adder Tree 전용 출력 포트 (새로 추가됨) ---
    output logic                          adder_tree_valid_out_arr [4][13],
    output logic [WORD_WIDTH-1:0]         adder_tree_result_arr    [4][13]
);

    //=========================================================================
    // 상수 및 오프셋 정의
    //=========================================================================
    localparam STEP1_SIZE  = 208;
    localparam STEP2_SIZE  = 169; // 13 * 13
    localparam STEP2_TOTAL_SIZE = 676; // 4 * 169
    localparam MU140_SIZE  = 140;

    localparam STEP1_END_IDX   = STEP1_SIZE - 1;                           // 207
    localparam STEP2_START_IDX = STEP1_END_IDX + 1;                       // 208
    localparam STEP2_END_IDX   = STEP2_START_IDX + STEP2_TOTAL_SIZE - 1;  // 883
    localparam MU140_START_IDX = STEP2_END_IDX + 1;                       // 884
    
    //=========================================================================
    // 내부 신호 선언
    //=========================================================================

    // --- modular_engine_step1 ---
    logic                       step1_valid_in_arr [13][16];
    logic                       step1_s_in_arr     [13][16];
    logic [2:0]                 step1_mode_arr     [13][16];
    logic [WORD_WIDTH-1:0]      step1_A_arr        [13][16];
    logic [WORD_WIDTH-1:0]      step1_B_arr        [13][16];
    logic [WORD_WIDTH-1:0]      step1_q_arr        [13][16];
    logic [2*WORD_WIDTH-1:0]    step1_mu_arr       [13][16];
    logic [5:0]                 step1_q_width_arr  [13][16];
    logic                       step1_valid_out_arr[13][16];
    logic [WORD_WIDTH-1:0]      step1_result_arr   [13][16];
    
    // --- MU_140 ---
    logic                       mu140_valid_in_arr [140];
    logic                       mu140_s_in_arr     [140];
    logic [2:0]                 mu140_mode_arr     [140];
    logic [WORD_WIDTH-1:0]      mu140_A_arr        [140];
    logic [WORD_WIDTH-1:0]      mu140_B_arr        [140];
    logic [WORD_WIDTH-1:0]      mu140_q_arr        [140];
    logic [2*WORD_WIDTH-1:0]    mu140_mu_arr       [140];
    logic [5:0]                 mu140_q_width_arr  [140];
    logic                       mu140_valid_out_arr[140];
    logic [WORD_WIDTH-1:0]      mu140_result_arr   [140];

    // --- modular_engine_step2 (4개) ---
    logic                       step2_valid_in_arr [4][13][13];
    logic                       step2_s_in_arr     [4][13][13];
    logic [2:0]                 step2_mode_arr     [4][13][13];
    logic [WORD_WIDTH-1:0]      step2_A_arr        [4][13][13];
    logic [WORD_WIDTH-1:0]      step2_B_arr        [4][13][13];
    logic [WORD_WIDTH-1:0]      step2_q_arr        [4][13][13];
    logic [2*WORD_WIDTH-1:0]    step2_mu_arr       [4][13][13];
    logic [5:0]                 step2_q_width_arr  [4][13][13];
    logic                       step2_valid_out_arr[4][13][13];
    logic [WORD_WIDTH-1:0]      step2_result_arr   [4][13][13];
    
    // --- adder_tree_13 (4개) ---
    logic                       addertree_valid_in_arr_internal [4][13];
    logic [WORD_WIDTH-1:0]      addertree_q_arr_internal        [4][13];
    logic                       addertree_valid_out_arr_internal[4][13];
    logic [WORD_WIDTH-1:0]      addertree_sum_arr_internal      [4][13];
    
    //=========================================================================
    // 입력 분배 로직
    //=========================================================================
    always_comb begin
        int offset;
        // 1. step1 (208개: 0 ~ 207)
        for (int i = 0; i < 13; i++) begin
            for (int j = 0; j < 16; j++) begin
                offset = i * 16 + j;
                step1_valid_in_arr[i][j] = valid_in_arr[offset];
                step1_s_in_arr[i][j]     = s_in_arr[offset];
                step1_mode_arr[i][j]     = mode_arr[offset];
                step1_A_arr[i][j]        = A_arr[offset];
                step1_B_arr[i][j]        = B_arr[offset];
                step1_q_arr[i][j]        = q_arr[offset];
                step1_mu_arr[i][j]       = mu_arr[offset];
                step1_q_width_arr[i][j]  = q_width_arr[offset];
            end
        end

        // 2. step2 (676개: 208 ~ 883)
        for (int i = 0; i < 4; i++) begin
            for (int j = 0; j < 13; j++) begin
                for (int k = 0; k < 13; k++) begin
                    offset = STEP2_START_IDX + i * STEP2_SIZE + j * 13 + k;
                    step2_valid_in_arr[i][j][k] = valid_in_arr[offset];
                    step2_s_in_arr[i][j][k]     = s_in_arr[offset];
                    step2_mode_arr[i][j][k]     = mode_arr[offset];
                    step2_A_arr[i][j][k]        = A_arr[offset];
                    step2_B_arr[i][j][k]        = B_arr[offset];
                    step2_q_arr[i][j][k]        = q_arr[offset];
                    step2_mu_arr[i][j][k]       = mu_arr[offset];
                    step2_q_width_arr[i][j][k]  = q_width_arr[offset];
                end
            end
        end

        // 3. mu140 (140개: 884 ~ 1023)
        for (int i = 0; i < MU140_SIZE; i++) begin
            offset = MU140_START_IDX + i;
            mu140_valid_in_arr[i] = valid_in_arr[offset];
            mu140_s_in_arr[i]     = s_in_arr[offset];
            mu140_mode_arr[i]     = mode_arr[offset];
            mu140_A_arr[i]        = A_arr[offset];
            mu140_B_arr[i]        = B_arr[offset];
            mu140_q_arr[i]        = q_arr[offset];
            mu140_mu_arr[i]       = mu_arr[offset];
            mu140_q_width_arr[i]  = q_width_arr[offset];
        end
    end

    //=========================================================================
    // 모듈 인스턴스화
    //=========================================================================

    // --- 1. modular_engine_step1 ---
    modular_engine_step1 #(
        .WORD_WIDTH(WORD_WIDTH)
    ) u_modular_engine_step1 (
        .clk              (clk),
        .rst_n            (rst_n),
        .valid_in_arr     (step1_valid_in_arr),
        .s_in_arr         (step1_s_in_arr),
        .mode_arr         (step1_mode_arr),
        .A_arr            (step1_A_arr),
        .B_arr            (step1_B_arr),
        .q_arr            (step1_q_arr),
        .mu_arr           (step1_mu_arr),
        .q_width_arr      (step1_q_width_arr),
        .valid_out_arr    (step1_valid_out_arr),
        .result_arr       (step1_result_arr)
    );

    // --- 2. MU_140 ---
    MU_140 #(
        .WORD_WIDTH(WORD_WIDTH)
    ) u_MU_140 (
        .clk              (clk),
        .rst_n            (rst_n),
        .valid_in_arr     (mu140_valid_in_arr),
        .s_in_arr         (mu140_s_in_arr),
        .mode_arr         (mu140_mode_arr),
        .A_arr            (mu140_A_arr),
        .B_arr            (mu140_B_arr),
        .q_arr            (mu140_q_arr),
        .mu_arr           (mu140_mu_arr),
        .q_width_arr      (mu140_q_width_arr),
        .valid_out_arr    (mu140_valid_out_arr),
        .result_arr       (mu140_result_arr)
    );

    // --- 3 & 4. modular_engine_step2 와 adder_tree_13 (generate로 4세트 생성) ---
    generate
        for (genvar i = 0; i < 4; i++) begin : gen_step2_path
            
            // --- modular_engine_step2 인스턴스 ---
            modular_engine_step2 #(
                .WORD_WIDTH(WORD_WIDTH)
            ) u_modular_engine_step2 (
                .clk              (clk),
                .rst_n            (rst_n),
                .valid_in_arr     (step2_valid_in_arr[i]),
                .s_in_arr         (step2_s_in_arr[i]),
                .mode_arr         (step2_mode_arr[i]),
                .A_arr            (step2_A_arr[i]),
                .B_arr            (step2_B_arr[i]),
                .q_arr            (step2_q_arr[i]),
                .mu_arr           (step2_mu_arr[i]),
                .q_width_arr      (step2_q_width_arr[i]),
                .valid_out_arr    (step2_valid_out_arr[i]),
                .result_arr       (step2_result_arr[i])
            );

            // --- adder_tree_13을 위한 입력 신호 생성 ---
            always_comb begin
                for (int j = 0; j < 13; j++) begin
                    // addertree_valid_in_arr_internal[i][j] = &step2_valid_out_arr[i][j]; 
                    logic tmp_valid;
                    tmp_valid = 1'b1;
                    for (int k = 0; k < 13; k++) begin
                        tmp_valid &= step2_valid_out_arr[i][j][k];
                    end
                    addertree_valid_in_arr_internal[i][j] = tmp_valid;
                    addertree_q_arr_internal[i][j]        = step2_q_arr[i][j][0];
                end
            end

            // --- adder_tree_13 인스턴스 ---
            adder_tree_13 #(
                .WIDTH(WORD_WIDTH),
                .MAX_INPUTS(MAX_INPUTS)
            ) u_adder_tree_13 (
                .clk               (clk),
                .rst_n             (rst_n),
                .i_valid_arr       (addertree_valid_in_arr_internal[i]),
                .i_inputs_arr      (step2_result_arr[i]),
                .i_input_count_arr (adder_tree_input_count_arr[i]),
                .i_q_arr           (addertree_q_arr_internal[i]),
                .o_valid_arr       (addertree_valid_out_arr_internal[i]),
                .o_sum_arr         (addertree_sum_arr_internal[i])
            );

        end
    endgenerate

    //=========================================================================
    // 출력 병합 및 Demux 로직 (수정된 로직)
    //=========================================================================
    always_comb begin
        int offset;
        // 1. step1 출력 (208개: 0 ~ 207)
        for (int i = 0; i < 13; i++) begin
            for (int j = 0; j < 16; j++) begin
                offset = i * 16 + j;
                valid_out_arr[offset] = step1_valid_out_arr[i][j];
                result_arr[offset]    = step1_result_arr[i][j];
            end
        end

        // 2. step2 경로 출력 (Demux 로직, 676개: 208 ~ 883)
        for (int i = 0; i < 4; i++) begin
            if (step2_mode[i]) begin 
                // Adder Tree 경로: step2의 출력이 adder tree로만 라우팅됨
                // 메인 출력 버스의 해당 구간은 유효하지 않음(0)으로 처리
                for (int j = 0; j < STEP2_SIZE; j++) begin
                     offset = STEP2_START_IDX + i * STEP2_SIZE + j;
                     valid_out_arr[offset] = 1'b0; 
                     result_arr[offset]    = '0;
                end
            end else begin
                // Bypass 경로: step2의 출력이 메인 출력 버스로 바로 연결됨
                for (int j = 0; j < 13; j++) begin
                    for (int k = 0; k < 13; k++) begin
                        offset = STEP2_START_IDX + i * STEP2_SIZE + j * 13 + k;
                        valid_out_arr[offset] = step2_valid_out_arr[i][j][k];
                        result_arr[offset]    = step2_result_arr[i][j][k];
                    end
                end
            end
        end

        // 3. mu140 출력 (140개: 884 ~ 1023)
        for (int i = 0; i < MU140_SIZE; i++) begin
            offset = MU140_START_IDX + i;
            valid_out_arr[offset] = mu140_valid_out_arr[i];
            result_arr[offset]    = mu140_result_arr[i];
        end
    end

    // --- 4. Adder Tree 출력을 새 포트로 직접 연결 ---
    assign adder_tree_result_arr = addertree_sum_arr_internal;
    assign adder_tree_valid_out_arr = addertree_valid_out_arr_internal;

endmodule



//=============================================================================
// 140개의 모듈러 연산 유닛 (SystemVerilog 버전)
//- modular_unit 140개 인스턴스 포함
//- 입출력 포트를 배열(array)로 선언
//=============================================================================
module MU_140 #(
    parameter int WORD_WIDTH = 60 // 데이터 비트 폭 파라미터
)(
    input  logic                          clk,      // 공통 클럭
    input  logic                          rst_n,    // 공통 리셋 (active low)

    // --- 140개 유닛을 위한 Control & Data Inputs (배열 타입) ---
    input  logic                          valid_in_arr [140], // 입력 유효 신호 배열
    input  logic                          s_in_arr     [140], // s_in 신호 배열
    input  logic [2:0]                    mode_arr     [140], // 연산 모드 배열
    input  logic [WORD_WIDTH-1:0]         A_arr        [140], // 피연산자 A 배열
    input  logic [WORD_WIDTH-1:0]         B_arr        [140], // 피연산자 B 배열
    input  logic [WORD_WIDTH-1:0]         q_arr        [140], // 모듈러스 q 배열
    input  logic [2*WORD_WIDTH-1:0]       mu_arr       [140], // Barrett 곱셈용 상수 mu 배열
    input  logic [5:0]                    q_width_arr  [140], // q_width 배열

    // --- 140개 유닛의 Control & Data Outputs (배열 타입) ---
    output logic                          valid_out_arr[140], // 출력 유효 신호 배열
    output logic [WORD_WIDTH-1:0]         result_arr   [140]  // 연산 결과 배열
);

    //-------------------------------------------------------------------------
    // 140개의 modular_unit 인스턴스 생성
    //-------------------------------------------------------------------------
    generate
        for (genvar i = 0; i < 140; i++) begin : gen_mu_instance
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