`timescale 1ns/1ps

module tb_modular_engine_bconv_pipelined;

    // =========================================================================
    // 파라미터 및 상수 정의
    // =========================================================================
    localparam int WORD_WIDTH     = 60;
    localparam int N              = 65536; // 2^16
    localparam int NUM_Q          = 13;    // L+1
    localparam int NUM_P          = 5;     // K
    localparam int COEFFS_PER_CLK = 16;
    localparam int STEP1_UNITS    = NUM_Q * COEFFS_PER_CLK; // 13 * 16 = 208
    localparam int STEP2_UNITS_PER_GROUP = 169; // 13 * 13
    localparam int STEP2_START_IDX = 208;
    localparam int TOTAL_UNITS    = 1024;
    
    localparam int NUM_CYCLES_STEP1 = N / COEFFS_PER_CLK;     // 4096
    localparam int NUM_CYCLES_STEP2 = N / 4;                  // 16384
    
    localparam logic [2:0] MODE_MULT = 3'b011;

    localparam time CLK_PERIOD = 2ns;

    // =========================================================================
    // 테스트벤치 신호 및 메모리 선언
    // =========================================================================
    logic                          clk;
    logic                          rst_n;

    // --- DUT 입출력 ---
    logic                          valid_in_arr [TOTAL_UNITS];
    logic                          s_in_arr     [TOTAL_UNITS];
    logic [2:0]                    mode_arr     [TOTAL_UNITS];
    logic [WORD_WIDTH-1:0]         A_arr        [TOTAL_UNITS];
    logic [WORD_WIDTH-1:0]         B_arr        [TOTAL_UNITS];
    logic [WORD_WIDTH-1:0]         q_arr        [TOTAL_UNITS];
    logic [2*WORD_WIDTH-1:0]       mu_arr       [TOTAL_UNITS];
    logic [5:0]                    q_width_arr  [TOTAL_UNITS];
    logic                          step2_mode [4];
    logic [3:0]                    adder_tree_input_count_arr [4][13];
    logic                          valid_out_arr [TOTAL_UNITS];
    logic [WORD_WIDTH-1:0]         result_arr    [TOTAL_UNITS];
    logic                          adder_tree_valid_out_arr [4][13];
    logic [WORD_WIDTH-1:0]         adder_tree_result_arr    [4][13];

    // --- 테스트 벡터 메모리 ---
    logic [WORD_WIDTH-1:0] coeffs_q_mem       [NUM_Q][N];
    logic [WORD_WIDTH-1:0] step1_golden_mem   [NUM_Q][N];
    logic [WORD_WIDTH-1:0] q_hat_inv_mem      [NUM_Q];
    logic [WORD_WIDTH-1:0] basis_q_mem        [NUM_Q];
    logic [2*WORD_WIDTH-1:0] mu_q_mem         [NUM_Q];
    logic [WORD_WIDTH-1:0] q_hat_mod_p_mem [NUM_P][NUM_Q];
    logic [WORD_WIDTH-1:0] basis_p_mem     [NUM_P];
    logic [2*WORD_WIDTH-1:0] mu_p_mem      [NUM_P];
    logic [WORD_WIDTH-1:0] final_golden_mem[NUM_P][N];
    
    // --- 결과 버퍼 ---
    logic [WORD_WIDTH-1:0] step1_result_buffer[NUM_Q][N];
    logic [WORD_WIDTH-1:0] final_result_buffer[NUM_P][N];
    
    // --- 동기화 및 에러 카운팅 ---
    integer error_count = 0;
    logic step1_cols_ready = 0; // Step 2 시작 동기화를 위한 카운터

    // =========================================================================
    // DUT (Device Under Test) 인스턴스화
    // =========================================================================
    modular_engine #(.WORD_WIDTH(WORD_WIDTH)) dut (.*);

    // =========================================================================
    // 클럭 생성
    // =========================================================================
    always #((CLK_PERIOD)/2) clk = ~clk;

    // =========================================================================
    // 테스트 시나리오
    // =========================================================================
    initial begin
        $display("==========================================================");
        $display("== BConv Pipelined (Step 1 & 2) Testbench Started      ==");
        $display("==========================================================");
        
        initialize();
        load_vectors();
        reset_dut();

        // --- Step 1과 Step 2를 병렬로 실행 ---
        $display("\n[INFO] Starting Step 1 and Step 2 simulations in parallel...");
        fork
            run_step1_simulation();
            run_step2_simulation();
        join
        
        // --- 모든 시뮬레이션 완료 후 결과 검증 ---
        $display("\n[INFO] All simulations finished. Verifying results...");
        verify_step1_results();
        verify_step2_results();
        
        // --- 최종 결과 ---
        if (error_count == 0) begin
            $display("\n[SUCCESS] All Step 1 & 2 results match. TEST PASSED!");
        end else begin
            $error("\n[FAILURE] Found %0d total mismatches. TEST FAILED!", error_count);
        end
        $display("==========================================================");
        $stop;
    end

    // --- 초기화, 리셋, 파일 로드 태스크 (이전과 동일) ---
    task initialize;
        clk = 1'b0;
        rst_n = 1'b0;
        valid_in_arr = '{default:0}; s_in_arr = '{default:0}; mode_arr = '{default:0};
        A_arr = '{default:0}; B_arr = '{default:0}; q_arr = '{default:0}; mu_arr = '{default:0};
        q_width_arr = '{default:0}; step2_mode = '{default:0}; adder_tree_input_count_arr = '{default:0};
    endtask

    task reset_dut;
        #10;
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        $display("[INFO] Reset complete.");
        repeat(2) @(posedge clk);
    endtask
    
    task load_vectors;
        logic [WORD_WIDTH-1:0] transposed_coeffs_q_mem[N][NUM_Q], transposed_step1_golden_mem[N][NUM_Q];
        logic [WORD_WIDTH-1:0] transposed_q_hat_mod_p_mem[NUM_Q][NUM_P];
        $display("[INFO] Loading all test vectors from files...");
        $readmemh("./bconv_test_vectors/coeffs_q.txt", coeffs_q_mem);
        $readmemh("./bconv_test_vectors/step1_results.txt", step1_golden_mem);
        $readmemh("./bconv_test_vectors/q_hat_inv.txt", q_hat_inv_mem);
        $readmemh("./bconv_test_vectors/basis_q.txt", basis_q_mem);
        $readmemh("./bconv_test_vectors/mu_q.txt", mu_q_mem);
        $readmemh("./bconv_test_vectors/mu_p.txt", mu_p_mem);
        $readmemh("./bconv_test_vectors/q_hat_mod_p.txt", q_hat_mod_p_mem);
        $readmemh("./bconv_test_vectors/basis_p.txt", basis_p_mem);
        $readmemh("./bconv_test_vectors/final_conversion_results.txt", final_golden_mem);
        // for (int i=0; i<NUM_Q; i++) for (int j=0; j<N; j++) coeffs_q_mem[i][j] = transposed_coeffs_q_mem[j][i];
        // for (int i=0; i<NUM_Q; i++) for (int j=0; j<N; j++) step1_golden_mem[i][j] = transposed_step1_golden_mem[j][i];
        // for (int i=0; i<NUM_P; i++) for (int j=0; j<NUM_Q; j++) q_hat_mod_p_mem[i][j] = transposed_q_hat_mod_p_mem[j][i];
        // for (int i=0; i<NUM_P; i++) mu_p_mem[i] = (1 << (2 * WORD_WIDTH)) / basis_p_mem[i];
        $display("[INFO] Test vectors loaded and processed successfully.");
    endtask

    // --- Step 1 시뮬레이션 태스크 ---
    task run_step1_simulation;
        int cycle, col_offset, col_offset_buffer;
        int idx, i, j;
        for (cycle = 0; cycle < NUM_CYCLES_STEP1; cycle++) begin
            @(posedge clk);
            // valid_in_arr = '{default:0}; // 매 사이클 입력 초기화
            col_offset = cycle * COEFFS_PER_CLK;
            // Step 1 입력 인가 (0~207 유닛)
            for (i = 0; i < NUM_Q; i++) begin 
                for (j = 0; j < COEFFS_PER_CLK; j++) begin
                    idx = i * COEFFS_PER_CLK + j;
                    A_arr[idx] = coeffs_q_mem[i][col_offset + j];
                    B_arr[idx] = q_hat_inv_mem[i];
                    q_arr[idx] = basis_q_mem[i];
                    mu_arr[idx] = mu_q_mem[i];
                    valid_in_arr[idx] = 1'b1;
                    mode_arr[idx] = MODE_MULT;
                    q_width_arr[idx] = WORD_WIDTH;
                end
            end
            
            if (cycle > 4) begin
                col_offset_buffer = (cycle - 5) * COEFFS_PER_CLK;
                for (i = 0; i < NUM_Q; i++) begin
                    for (j = 0; j < COEFFS_PER_CLK; j++) begin
                        idx = i * COEFFS_PER_CLK + j;
                        step1_result_buffer[i][col_offset_buffer + j] = result_arr[idx];
                    end
                end
                step1_cols_ready = 1;
            end

            // Step 2에 데이터가 준비되었음을 알림
            // step1_cols_ready += COEFFS_PER_CLK;

            if ((cycle+1) % 512 == 0) $display("  -> Step 1 Cycle %0d/%0d completed.", cycle+1, NUM_CYCLES_STEP1);
        end
        @(posedge clk);
        valid_in_arr = '{default:0};
    endtask

    // --- Step 2 시뮬레이션 태스크 ---
    task run_step2_simulation;
        int cycle, col_offset, current_col, col_offset_save;
        int i, j, k, idx;
        logic [WORD_WIDTH-1:0] a_val;
        step2_mode = '{default: 1};
        adder_tree_input_count_arr = '{default: 13};

        wait(step1_cols_ready == 1);
        for (cycle = 0; cycle < NUM_CYCLES_STEP2; cycle++) begin
            col_offset = cycle * 4;

            // Step 2 연산에 필요한 Step 1 결과가 준비될 때까지 대기
            
            @(posedge clk);

            // valid_in_arr = '{default:0}; // 입력 초기화

            // Step 2 입력 할당
            for (i = 0; i < 4; i++) begin // 4개의 step2 그룹
                current_col = col_offset + i;
                for (j = 0; j < NUM_Q; j++) begin // 각 그룹 내 13개 행
                    // --- 활성/비활성 행 구분 ---
                    if (j < NUM_P) begin // 활성 행 (j = 0 to 4)
                        for (k = 0; k < NUM_Q; k++) begin // 각 행 내 13개 유닛
                            idx = STEP2_START_IDX + i * STEP2_UNITS_PER_GROUP + j * NUM_Q + k;
                            // A_arr: step1 결과값을 브로드캐스팅
                            A_arr[idx] = step1_result_buffer[k][current_col];
                            // B_arr, q_arr 등: p 관련 파라미터 할당
                            B_arr[idx] = q_hat_mod_p_mem[j][k];
                            q_arr[idx] = basis_p_mem[j];
                            mu_arr[idx] = mu_p_mem[j];
                            valid_in_arr[idx] = 1'b1;
                            mode_arr[idx] = MODE_MULT;
                            q_width_arr[idx] = WORD_WIDTH;
                        end
                    end else begin // 비활성 행 (j = 5 to 12)
                        for (k = 0; k < NUM_Q; k++) begin // 각 행 내 13개 유닛
                            idx = STEP2_START_IDX + i * STEP2_UNITS_PER_GROUP + j * NUM_Q + k;
                            // 모든 입력을 0 / invalid로 설정
                            A_arr[idx] = '0;
                            B_arr[idx] = '0;
                            q_arr[idx] = '0;
                            mu_arr[idx] = '0;
                            valid_in_arr[idx] = 1'b0;
                            mode_arr[idx] = '0;
                            q_width_arr[idx] = '0;
                        end
                    end
                end
            end
            
            // Step 2 (Adder Tree) 결과 대기 및 수집
            // while (!adder_tree_valid_out_arr[0][0]) @(posedge clk);
            if (cycle > 8) begin
                col_offset_save = (cycle-9) * 4;
                for (i = 0; i < 4; i++) begin
                    for (j = 0; j < NUM_P; j++) begin
                        final_result_buffer[j][col_offset_save + i] = adder_tree_result_arr[i][j];
                    end
                end
            end

            if ((cycle+1) % 2048 == 0) $display("  -> Step 2 Cycle %0d/%0d completed.", cycle+1, NUM_CYCLES_STEP2);
        end
    endtask

    // --- 결과 검증 태스크 (Step 1) ---
    task verify_step1_results;
        for (int i=0; i<NUM_Q; i++) begin
            for (int j=0; j<N; j++) begin
                if (step1_result_buffer[i][j] !== step1_golden_mem[i][j]) begin
                    $error("Step 1 Mismatch @ [%0d][%0d]! DUT: %h, Golden: %h", i, j, step1_result_buffer[i][j], step1_golden_mem[i][j]);
                    error_count++;
                    if (error_count > 20) return;
                end
            end
        end
    endtask

    // --- 결과 검증 태스크 (Step 2) ---
    task verify_step2_results;
        for (int i = 0; i < NUM_P; i++) begin 
            for (int j = 0; j < N; j++) begin
                if (final_result_buffer[i][j] !== final_golden_mem[i][j]) begin
                    $error("Step 2 Mismatch @ [%0d][%0d]! DUT: %h, Golden: %h", i, j, final_result_buffer[i][j], final_golden_mem[i][j]);
                    error_count++;
                    if (error_count > 20) return;
                end
            end
        end
    endtask

endmodule
















// `timescale 1ns/1ps

// module tb_modular_engine_bconv_step1;

//     // =========================================================================
//     // 파라미터 및 상수 정의
//     // =========================================================================
//     localparam int WORD_WIDTH     = 60;
//     localparam int N              = 65536; // 2^16
//     localparam int NUM_Q          = 13;    // L+1
//     localparam int COEFFS_PER_CLK = 16;
//     localparam int STEP1_UNITS    = NUM_Q * COEFFS_PER_CLK; // 13 * 16 = 208
//     localparam int TOTAL_UNITS    = 1024;
//     localparam int NUM_CYCLES     = N / COEFFS_PER_CLK;     // 65536 / 16 = 4096
    
//     localparam logic [2:0] MODE_MULT = 3'b011;

//     // Clock 주기
//     localparam time CLK_PERIOD = 2ns;

//     // DUT의 Latency (가정). 실제 설계에 맞게 조절 필요
//     // valid_out을 모니터링하여 유동적으로 처리
//     localparam int DUT_LATENCY = 5; 

//     // =========================================================================
//     // 테스트벤치 신호 선언
//     // =========================================================================
//     logic                          clk;
//     logic                          rst_n;

//     // --- DUT 입력 ---
//     logic                          valid_in_arr [TOTAL_UNITS];
//     logic                          s_in_arr     [TOTAL_UNITS];
//     logic [2:0]                    mode_arr     [TOTAL_UNITS];
//     logic [WORD_WIDTH-1:0]         A_arr        [TOTAL_UNITS];
//     logic [WORD_WIDTH-1:0]         B_arr        [TOTAL_UNITS];
//     logic [WORD_WIDTH-1:0]         q_arr        [TOTAL_UNITS];
//     logic [2*WORD_WIDTH-1:0]       mu_arr       [TOTAL_UNITS];
//     logic [5:0]                    q_width_arr  [TOTAL_UNITS];
//     logic                          step2_mode [4];
//     logic [3:0]                    adder_tree_input_count_arr [4][13];
    
//     // --- DUT 출력 ---
//     logic                          valid_out_arr [TOTAL_UNITS];
//     logic [WORD_WIDTH-1:0]         result_arr    [TOTAL_UNITS];
//     // 사용하지 않는 출력
//     logic                          adder_tree_valid_out_arr [4][13];
//     logic [WORD_WIDTH-1:0]         adder_tree_result_arr    [4][13];

//     // =========================================================================
//     // 테스트 벡터 저장을 위한 메모리
//     // =========================================================================
//     // Python 스크립트는 [NUM_Q][N] 배열을 전치(transpose)하여 [N][NUM_Q] 형태로 파일에 씁니다.
//     // 따라서 [N][NUM_Q]로 읽은 후, 테스트벤치 내에서 다시 전치하여 사용합니다.
//     logic [WORD_WIDTH-1:0] transposed_coeffs_q_mem  [N][NUM_Q];
//     logic [WORD_WIDTH-1:0] transposed_step1_golden_mem [N][NUM_Q];

//     // 실제 테스트 로직에서 사용할 전치된 메모리
//     logic [WORD_WIDTH-1:0] coeffs_q_mem  [NUM_Q][N];
//     logic [WORD_WIDTH-1:0] step1_golden_mem [NUM_Q][N];
    
//     // 파라미터 메모리
//     logic [WORD_WIDTH-1:0]   q_hat_inv_mem [NUM_Q];
//     logic [WORD_WIDTH-1:0]   basis_q_mem   [NUM_Q];
//     logic [2*WORD_WIDTH-1:0] mu_q_mem      [NUM_Q];

//     // DUT 결과를 저장할 버퍼
//     logic [WORD_WIDTH-1:0] step1_result_buffer [NUM_Q][N];
    
//     integer error_count = 0;
//     integer cycle_count = 0;

//     // =========================================================================
//     // DUT (Device Under Test) 인스턴스화
//     // =========================================================================
//     modular_engine #(
//         .WORD_WIDTH(WORD_WIDTH)
//     ) dut (
//         .clk              				(clk),
//         .rst_n            				(rst_n),
//         .valid_in_arr	  				(valid_in_arr),
//         .s_in_arr	  					(s_in_arr),
//         .mode_arr	  					(mode_arr),
//         .A_arr	  						(A_arr),
//         .B_arr	  						(B_arr),
//         .q_arr	  						(q_arr),
//         .mu_arr	  						(mu_arr),
//         .q_width_arr	  				(q_width_arr),
//         .step2_mode	  					(step2_mode),
//         .adder_tree_input_count_arr	  	(adder_tree_input_count_arr),
//         .valid_out_arr	  				(valid_out_arr),
//         .result_arr	  					(result_arr),
//         .adder_tree_valid_out_arr	  	(adder_tree_valid_out_arr),
//         .adder_tree_result_arr	  		(adder_tree_result_arr)
//     );

//     // =========================================================================
//     // 클럭 생성
//     // =========================================================================
//     always #((CLK_PERIOD)/2) clk = ~clk;

//     // =========================================================================
//     // 테스트 시나리오
//     // =========================================================================
//     initial begin
//         $display("==========================================================");
//         $display("== BConv Step 1 Testbench for modular_engine Started   ==");
//         $display("==========================================================");
        
//         // --- 1. 초기화 ---
//         initialize();
        
//         // --- 2. 테스트 벡터 파일 로드 ---
//         load_vectors();

//         // --- 3. 리셋 신호 인가 ---
//         reset_dut();

//         // --- 4. Step 1 연산 및 결과 저장 ---
//         $display("\n[INFO] Starting Step 1 Simulation for %0d cycles...", NUM_CYCLES);
//         run_step1_simulation();
        
//         // // --- 5. 결과 검증 ---
//         // $display("\n[INFO] Simulation finished. Verifying results...");
//         // verify_results();
        
//         // --- 6. 테스트 종료 ---
//         if (error_count == 0) begin
//             $display("\n[SUCCESS] All Step 1 results match the golden vectors. TEST PASSED!");
//         end else begin
//             $error("\n[FAILURE] Found %0d mismatches in Step 1 results. TEST FAILED!", error_count);
//         end
//         $display("==========================================================");
//         $stop;
//     end

//     // --- 초기화 태스크 ---
//     task initialize;
//         clk = 1'b0;
//         rst_n = 1'b0;
//         valid_in_arr = '{default:0};
//         s_in_arr     = '{default:0};
//         mode_arr     = '{default:0};
//         A_arr        = '{default:0};
//         B_arr        = '{default:0};
//         q_arr        = '{default:0};
//         mu_arr       = '{default:0};
//         q_width_arr  = '{default:0};
//         step2_mode   = '{default:0};
//         adder_tree_input_count_arr = '{default:0};
//     endtask

//     // --- 리셋 태스크 ---
//     task reset_dut;
//         #10;
//         rst_n = 1'b0;
//         repeat(5) @(posedge clk);
//         rst_n = 1'b1;
//         $display("[INFO] Reset complete.");
//         repeat(2) @(posedge clk);
//     endtask
    
//     // --- 파일 로드 태스크 ---
//     task load_vectors;
//         $display("[INFO] Loading test vectors from files...");
//         // Python 스크립트가 (N x NUM_Q) 형태로 저장하므로 그대로 읽음
//         $readmemh("./bconv_test_vectors/coeffs_q.txt", coeffs_q_mem);
//         $readmemh("./bconv_test_vectors/step1_results.txt", step1_golden_mem);

//         // 파라미터 파일 로드 (1D)
//         $readmemh("./bconv_test_vectors/q_hat_inv.txt", q_hat_inv_mem);
//         $readmemh("./bconv_test_vectors/basis_q.txt", basis_q_mem);
//         $readmemh("./bconv_test_vectors/mu_q.txt", mu_q_mem);

//         // 로드된 2D 배열을 테스트에 사용하기 편한 형태로 전치
//         // for (int i = 0; i < NUM_Q; i++) begin
//         //     for (int j = 0; j < N; j++) begin
//         //         coeffs_q_mem[i][j] = transposed_coeffs_q_mem[j][i];
//         //         step1_golden_mem[i][j] = transposed_step1_golden_mem[j][i];
//         //     end
//         // end
//         $display("[INFO] Test vectors loaded and transposed successfully.");
//     endtask

//     // --- Step 1 시뮬레이션 태스크 ---
//     task run_step1_simulation;
// 		int col_offset, col_offset_buffer;
//     	int i, j, idx, cycle;
//         for (cycle = 0; cycle < NUM_CYCLES; cycle++) begin
//             @(posedge clk);

//             // // 입력 초기화
//             // valid_in_arr = '{default:0};
//             // A_arr        = '{default:0};
//             // B_arr        = '{default:0};
//             // q_arr        = '{default:0};
//             // mu_arr       = '{default:0};
//             // mode_arr     = '{default:0};
//             // q_width_arr  = '{default:0};

//             // 현재 사이클에 해당하는 입력 데이터 할당
//             col_offset = cycle * COEFFS_PER_CLK;
//             for (i = 0; i < NUM_Q; i++) begin
//                 for (j = 0; j < COEFFS_PER_CLK; j++) begin
//                     idx = i * COEFFS_PER_CLK + j;
                    
//                     A_arr[idx]       = coeffs_q_mem[i][col_offset + j];
//                     B_arr[idx]       = q_hat_inv_mem[i];
//                     q_arr[idx]       = basis_q_mem[i];
//                     mu_arr[idx]      = mu_q_mem[i];
//                     valid_in_arr[idx]= 1'b1;
//                     mode_arr[idx]    = MODE_MULT;
//                     q_width_arr[idx] = WORD_WIDTH;
//                 end
//             end
//             s_in_arr = '{default:0}; // s_in은 항상 0

//             // // 유효 출력이 나올 때까지 대기
//             // while (!valid_out_arr[0]) begin
//             //     @(posedge clk);
//             // end

//             // 출력을 버퍼에 저장
//             if (cycle > 4) begin
//                 col_offset_buffer = (cycle - 5) * COEFFS_PER_CLK;
//                 for (i = 0; i < NUM_Q; i++) begin
//                     for (j = 0; j < COEFFS_PER_CLK; j++) begin
//                         idx = i * COEFFS_PER_CLK + j;
//                         step1_result_buffer[i][col_offset_buffer + j] = result_arr[idx];
//                     end
//                 end
//             end

//             if ((cycle+1) % 512 == 0) begin
//                  $display("  -> Cycle %0d/%0d: Inputs driven and results captured.", cycle+1, NUM_CYCLES);
//             end
//         end
//         @(posedge clk);
//         valid_in_arr = '{default:0}; // 마지막 입력 후 valid 비활성화
//     endtask

//     // --- 결과 검증 태스크 ---
//     task verify_results;
//         for (int i = 0; i < NUM_Q; i++) begin
//             for (int j = 0; j < N; j++) begin
//                 if (step1_result_buffer[i][j] !== step1_golden_mem[i][j]) begin
//                     $error("Mismatch found at index [%0d][%0d]!", i, j);
//                     $error("  - DUT Result: 0x%h", step1_result_buffer[i][j]);
//                     $error("  - Golden    : 0x%h", step1_golden_mem[i][j]);
//                     error_count++;
//                 end
//             end
//             if (error_count > 20) begin // 에러가 너무 많으면 중단
//                 $error("Too many errors, aborting verification.");
//                 return;
//             end
//         end
//     endtask

// endmodule