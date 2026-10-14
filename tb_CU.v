`timescale 1ns / 1ps

module tb_CU;

// ===================================================================
// Parameters
// ===================================================================
localparam DATA_WIDTH = 58;
localparam MAX_LEVEL  = 17; // Basis Q size = LEVEL + 1 = 13
localparam LEVEL      = 12; // Basis Q size = LEVEL + 1 = 13
localparam K          = 17; // Basis P size
localparam CLK_PERIOD = 4;  // Clock period in ns

// ===================================================================
// Signal Declarations
// ===================================================================
reg clk;
reg rst_n;
reg en_step_1;
reg en_step_2;
reg [4:0] level;
reg [DATA_WIDTH-1:0] coeff;
reg [DATA_WIDTH-1:0] param;
reg [DATA_WIDTH-1:0] q_in;
reg [DATA_WIDTH-1:0] ratio_precomp;

wire [DATA_WIDTH-1:0] CU_out;

// Internal testbench signals
integer i, j;
integer error_count;

// ===================================================================
// Memories for Test Vectors
// ===================================================================
reg [DATA_WIDTH-1:0] basis_q_mem [0:LEVEL];
reg [DATA_WIDTH-1:0] basis_p_mem [0:K-1];
reg [DATA_WIDTH-1:0] coeff_q_mem [0:LEVEL];
reg [DATA_WIDTH-1:0] q_hat_inv_mem [0:LEVEL];
reg [DATA_WIDTH-1:0] q_hat_mod_p_mem [0:K-1][0:LEVEL];
reg [DATA_WIDTH-1:0] shoup_ratio_q_mem [0:LEVEL];
reg [DATA_WIDTH-1:0] shoup_ratio_p_mem [0:K-1][0:LEVEL];

// Golden output vectors
reg [DATA_WIDTH-1:0] step1_results_golden [0:LEVEL];
reg [DATA_WIDTH-1:0] final_results_p_golden [0:K-1];

// ===================================================================
// DUT Instantiation
// ===================================================================
CU #(
    .DATA_WIDTH(DATA_WIDTH),
    .MAX_LEVEL(MAX_LEVEL)
) DUT (
    .clk(clk),
    .rst_n(rst_n),
    .en_step_1(en_step_1),
    .en_step_2(en_step_2),
    .level(level),
    .coeff(coeff),
    .param(param),
    .q_in(q_in),
    .ratio_precomp(ratio_precomp),
    .CU_out(CU_out)
);

// ===================================================================
// Clock Generator
// ===================================================================
always #(CLK_PERIOD/2) clk = ~clk;

// ===================================================================
// Main Test Sequence
// ===================================================================
initial begin
    // 1. Load test vectors from files
    $readmemh("./cu_test_vectors/basis_q.txt", basis_q_mem);
    $readmemh("./cu_test_vectors/basis_p.txt", basis_p_mem);
    $readmemh("./cu_test_vectors/coeff_q.txt", coeff_q_mem);
    $readmemh("./cu_test_vectors/q_hat_inv.txt", q_hat_inv_mem);
    $readmemh("./cu_test_vectors/q_hat_mod_p.txt", q_hat_mod_p_mem);
    $readmemh("./cu_test_vectors/shoup_z_pre_step1.txt", shoup_ratio_q_mem);
    $readmemh("./cu_test_vectors/shoup_z_pre_step2.txt", shoup_ratio_p_mem);
    $readmemh("./cu_test_vectors/step1_results.txt", step1_results_golden);
    $readmemh("./cu_test_vectors/final_conversion_results.txt", final_results_p_golden);
    
    // 2. Initialization and Reset
    clk = 0;
    rst_n = 1;
    en_step_1 = 0;
    en_step_2 = 0;
    level = LEVEL;
    coeff = 0;
    param = 0;
    q_in = 0;
    ratio_precomp = 0;
    error_count = 0;

    $display("INFO: Starting CU Testbench Simulation...");
    
    // Apply reset
    rst_n = 0;
    #(CLK_PERIOD * 2);
    rst_n = 1;
    #(CLK_PERIOD * 2);

    // -----------------------------------------------------------------
    // STEP 1: Calculate Gamma values and store in DUT's internal buffer
    // -----------------------------------------------------------------
    $display("INFO: Starting Step 1: Gamma Calculation...");

    for (i = 0; i <= LEVEL; i = i + 1) begin
        coeff         = coeff_q_mem[i];
        param         = q_hat_inv_mem[i];
        q_in          = basis_q_mem[i];
        ratio_precomp = shoup_ratio_q_mem[i];
        en_step_1 = 1;
        @(posedge clk);
    end

    en_step_1 = 0;
    coeff         = 0;
    param         = 0;
    q_in          = 0;
    ratio_precomp = 0;
    
    // -----------------------------------------------------------------
    // STEP 2: Calculate final results for each p_j in Basis P
    // -----------------------------------------------------------------
    $display("INFO: Starting Step 2: Final Result Calculation...");
    en_step_2 = 1;

    for (j = 0; j < K; j = j + 1) begin
        
        $display("INFO: Calculating for basis_p[%0d] = %h", j, basis_p_mem[j]);

        for (i = 0; i <= LEVEL; i = i + 1) begin
            param         = q_hat_mod_p_mem[j][i];
            q_in          = basis_p_mem[j];
            ratio_precomp = shoup_ratio_p_mem[j][i];
            // -------------------------------------------------------------
            // Verification
            // -------------------------------------------------------------
            if ((i == 3) && (j > 0)) begin
                if (CU_out === final_results_p_golden[j - 1]) begin
                    $display("SUCCESS: Test for p_%0d PASSED. DUT_out: %h, Golden: %h", j, CU_out, final_results_p_golden[j]);
                end else begin
                    $display("ERROR: Test for p_%0d FAILED. DUT_out: %h, Golden: %h", j, CU_out, final_results_p_golden[j]);
                    error_count = error_count + 1;
                end
            end
            @(posedge clk);
        end
        
    end

    @(posedge clk);
    en_step_2 = 0;
    q_in = 0;
    param         = 0;
    ratio_precomp = 0;

    @(posedge clk);
    @(posedge clk);
    @(posedge clk);
    
    if (CU_out === final_results_p_golden[16]) begin
        $display("SUCCESS: Test for p_%0d PASSED. DUT_out: %h, Golden: %h", 17, CU_out, final_results_p_golden[16]);
    end else begin
        $display("ERROR: Test for p_%0d FAILED. DUT_out: %h, Golden: %h", 17, CU_out, final_results_p_golden[16]);
        error_count = error_count + 1;
    end
    @(posedge clk);
    @(posedge clk);

    for (i = 0; i <= LEVEL; i = i + 1) begin
        if (DUT.buffer[i] === step1_results_golden[i]) begin
            $display("SUCCESS: Test for gamma_%0d PASSED. DUT_out: %h, Golden: %h", i, DUT.buffer[i], step1_results_golden[i]);
        end else begin
            $display("ERROR: Test for gamma_%0d FAILED. DUT_out: %h, Golden: %h", i, DUT.buffer[i], step1_results_golden[i]);
            error_count = error_count + 1;
        end
    end

    $display("INFO: Step 1 finished. All gamma values are now in DUT buffer.");

    // -----------------------------------------------------------------
    // Final Report
    // -----------------------------------------------------------------
    if (error_count == 0) begin
        $display("=====================================================");
        $display("======= ALL TESTS PASSED! Congratulations! =======");
        $display("=====================================================");
    end else begin
        $display("=====================================================");
        $display("======= SIMULATION FAILED with %0d errors. =======", error_count);
        $display("=====================================================");
    end

    $stop;
end

endmodule


















// `timescale 1ns / 1ps

// module CU_tb;

//     // --- 파라미터 정의 ---
//     parameter DATA_WIDTH = 58;
//     parameter LEVEL      = 12; // DUT의 버퍼 크기 (L=12)
//     parameter CLK_PERIOD = 4; // 클럭 주기 (4ns)

//     // --- 테스트벤치 신호 ---
//     reg clk;
//     reg rst_n;
//     reg mult_valid_in;
//     reg en_step_1;
//     reg [DATA_WIDTH-1:0] coeff;
//     reg [DATA_WIDTH-1:0] param;
//     reg [DATA_WIDTH-1:0] q_in;
//     reg [DATA_WIDTH-1:0] q_inv_in;

//     wire [DATA_WIDTH-1:0] CU_out;

//     // DUT의 내부 신호 모니터링
//     wire [DATA_WIDTH-1:0] monitor [0:LEVEL]; 

//     integer i;
//     integer error_count = 0;

//     // --- 테스트 벡터 저장을 위한 메모리 ---
//     reg [DATA_WIDTH-1:0] c_i_mem[0:LEVEL];
//     reg [DATA_WIDTH-1:0] param_mem[0:LEVEL];         // q_hat_inv_values.txt
//     reg [DATA_WIDTH-1:0] q_basis_mem[0:LEVEL];       // Q_basis.txt
//     reg [DATA_WIDTH-1:0] q_inv_mem[0:LEVEL];         // q_inv_values.txt
//     reg [DATA_WIDTH-1:0] gamma_mem[0:LEVEL];         // gamma_values.txt (비교 대상)
//     reg [DATA_WIDTH-1:0] param_step2_mem[0:LEVEL];         
//     reg [DATA_WIDTH-1:0] expected_mem[0:LEVEL];         
//     reg [DATA_WIDTH-1:0] p_basis_mem[0:LEVEL];  
//     reg [DATA_WIDTH-1:0] p_inv_mem[0:LEVEL];    

// 	initial begin
// 		// <<수정>>: 요청하신 파일 매핑에 따라 hex 파일 로드
//         $readmemh("../../RTL/test_vectors/c_i_values_mont.txt", c_i_mem);
//         $readmemh("../../RTL/test_vectors/q_hat_inv_values_mont.txt", param_mem); // param 입력으로 사용
//         $readmemh("../../RTL/test_vectors/Q_basis.txt", q_basis_mem);
//         $readmemh("../../RTL/test_vectors/q_inv_values.txt", q_inv_mem);
//         $readmemh("../../RTL/test_vectors/gamma_values_mont.txt", gamma_mem);
//         $readmemh("../../RTL/test_vectors/param_step2_p_0_mont.txt", param_step2_mem);
//         $readmemh("../../RTL/test_vectors/expected_x_j_mont.txt", expected_mem);
//         $readmemh("../../RTL/test_vectors/P_basis.txt", p_basis_mem);
//         $readmemh("../../RTL/test_vectors/p_inv_values.txt", p_inv_mem);
// 	end

//     // DUT(Design Under Test) 인스턴스
//     CU #(
//         .DATA_WIDTH(DATA_WIDTH),
//         .LEVEL(LEVEL)
//     ) dut (
//         .clk(clk),
//         .rst_n(rst_n),
//         .mult_valid_in(mult_valid_in),
//         .en_step_1(en_step_1),
//         .coeff(coeff),
//         .param(param),
//         .q_in(q_in),
//         .q_inv_in(q_inv_in),
//         .CU_out(CU_out)
//     );

//     // --- 클럭 생성 ---
//     always #((CLK_PERIOD)/2) clk = ~clk;

//     // --- 테스트 시퀀스 ---
//     initial begin
// 		$display("--- 시뮬레이션 시작 ---");

//         // 1. 초기화 및 파일 로드
//         $display("--- 시뮬레이션 시작: 입력 파일 로드 ---");
//         clk <= 0;
//         rst_n <= 1;
//         mult_valid_in <= 0;
//         en_step_1 <= 0;
//         coeff <= 0;
//         param <= 0;
//         q_in <= 0;
//         q_inv_in <= 0;

//         // 2. 리셋
//         rst_n <= 0;
//         #20;
//         rst_n <= 1;
//         @(posedge clk);

//         // 3. STEP 1: gamma 값 계산 및 검증
//         $display("--- STEP 1: gamma 값 계산 및 버퍼링 시작 ---");
        
//         for (i = 0; i <= LEVEL; i = i + 1) begin
//             @(posedge clk);
//             en_step_1 <= 1;

//             // <<수정>>: 메모리에서 읽어온 값들을 DUT 입력에 연결
//             coeff    <= c_i_mem[i];
//             param    <= param_mem[i];
//             q_in     <= q_basis_mem[i];
//             q_inv_in <= q_inv_mem[i];
        
//             mult_valid_in <= 1;
            
//             // 곱셈기 파이프라인 지연시간(latency) 만큼 대기 (예: 2 사이클)
//             @(posedge clk);
//             mult_valid_in <= 0;
//             @(posedge clk);
//             @(posedge clk);
//             @(posedge clk);

//             // @(posedge clk);
//             // @(posedge clk);
            
//             // // 검증: 곱셈기 출력이 예상 gamma 값과 일치하는지 확인
//             // if (dut.buffer[i] !== gamma_mem[i]) begin
//             //     $error("[STEP 1 FAILED] @ i=%0d, mismatch!", i);
//             //     $error("  DUT   modmult_out: %h", dut.buffer[i]);
//             //     $error("  Expected gamma:    %h", gamma_mem[i]);
//             //     error_count = error_count + 1;
//             // end else begin
//             //     $display("[STEP 1 PASSED] @ i=%0d, DUT_gamma: %h", i, dut.buffer[i]);
//             // end
//         end

//         @(posedge clk);
//         en_step_1 <= 0;
//         coeff    <= 0;
//         param    <= 0;
//         q_in     <= 0;
//         q_inv_in <= 0;

//         @(posedge clk);

//         // --- 4. <<추가>> STEP 2: 누적 합산 및 검증 ---
//         $display("--- STEP 2: 누적 합산 시작 (p_0에 대한 계산) ---");
        
//         // Step 2의 모듈러스는 p_0. 이 값들은 Python 스크립트에서 생성된
//         // P_basis.txt 와 P_basis에 대한 q_inv 파일에서 읽어와야 함 (여기서는 예시값 사용)
//         q_in     <= p_basis_mem[0]; // p_0
//         q_inv_in <= p_inv_mem[0]; // p_0에 대한 q_inv

//         for (i = 0; i <= LEVEL; i = i + 1) begin
//             @(posedge clk);
//             mult_valid_in <= 1;
//             param <= param_step2_mem[i]; // Step 2용 파라미터 로드
//             coeff <= 0; // en_step_1=0 이므로 MUX가 buffer 값을 선택. coeff는 Don't care.

//             // DUT 내부 파이프라인(곱셈->덧셈->레지스터 저장) 대기
//             @(posedge clk);
//             mult_valid_in <= 0;
//             @(posedge clk);
//             @(posedge clk);
//             @(posedge clk);
            
//             // 중간 누적 과정을 확인하고 싶다면 아래 라인의 주석을 해제
//             // $display("[STEP 2] Cycle %0d, Intermediate CU_out: %h", i, CU_out);
//         end
        
//         // 마지막 연산이 CU_out에 완전히 반영될 때까지 추가 대기
//         @(posedge clk);
//         @(posedge clk);
//         @(posedge clk);
//         @(posedge clk);

//         // --- 5. <<추가>> 최종 결과 검증 ---
//         if (CU_out !== expected_mem[0]) begin
//             $error("[STEP 2 FAILED] Final result mismatch!");
//             $error("  DUT CU_out:   %h", CU_out);
//             $error("  Expected val: %h", expected_mem[0]);
//             error_count = error_count + 1;
//         end else begin
//             $display("[STEP 2 PASSED] Final result: %h", CU_out);
//         end

//         #50;
        
//         if (error_count == 0) begin
//             $display("--- 모든 테스트 통과! ---");
//         end else begin
//             $display("--- %0d개의 에러 발생. 테스트 실패. ---", error_count);
//         end




        
//         #50;
        
//         if (error_count == 0) begin
//             $display("--- 모든 테스트 통과! ---");
//         end else begin
//             $display("--- %0d개의 에러 발생. 테스트 실패. ---", error_count);
//             $display("참고: param 입력이 몽고메리 곱셈 형식에 맞지 않아 에러가 발생했을 수 있습니다.");
//         end
        
//         $finish;
//     end

// endmodule