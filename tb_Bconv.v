`timescale 1ns / 1ps

module tb_Bconv;

    // 파라미터 선언
    parameter DATA_WIDTH = 58;
    localparam CLK_PERIOD = 4;       // Clock period in ns
    localparam LEVEL      = 12;       // Basis Q size = LEVEL + 1
    localparam K          = 17;      // Basis P size
    localparam NUM_CU     = 16;      // ADDED: DUT의 병렬 CU 개수와 일치시켜야 합니다.
    localparam NUM_COEFF  = 65536;      

    // 테스트벤치 신호 선언
    // Inputs
    reg clk;
    reg rst_n;
    reg start_Bconv;
    reg [4:0] level_in;
    reg [4:0] level_out;

    // CHANGED: DUT의 병렬 포트 폭에 맞게 수정 (NUM_CU * DATA_WIDTH)
    reg [NUM_CU * DATA_WIDTH-1:0] coeff;
    reg [NUM_CU * DATA_WIDTH-1:0] param;
    reg [NUM_CU * DATA_WIDTH-1:0] q_in;
    reg [NUM_CU * DATA_WIDTH-1:0] ratio_precomp;
    
    // 테스트 벡터 로드를 위한 메모리 (기존과 동일)
    reg [DATA_WIDTH-1:0] basis_q_mem [0:LEVEL];
    reg [DATA_WIDTH-1:0] basis_p_mem [0:K-1];
    reg [DATA_WIDTH-1:0] q_hat_inv_mem [0:LEVEL];
    reg [DATA_WIDTH-1:0] q_hat_mod_p_mem [0:K-1][0:LEVEL];
    reg [DATA_WIDTH-1:0] shoup_ratio_q_mem [0:LEVEL];
    reg [DATA_WIDTH-1:0] shoup_ratio_p_mem [0:K-1][0:LEVEL];
    reg [DATA_WIDTH-1:0] coeff_q_mem [0:NUM_COEFF-1][0:LEVEL];
    reg [DATA_WIDTH-1:0] step1_results_golden [0:NUM_COEFF-1][0:LEVEL];
    reg [DATA_WIDTH-1:0] final_results_p_golden [0:NUM_COEFF-1][0:K-1];
    reg [DATA_WIDTH-1:0] final_results_out [0:NUM_COEFF-1][0:K-1];
    integer i, j, k, l, m;
    integer error_count = 0;

    // Outputs
    // CHANGED: DUT의 병렬 포트 폭에 맞게 수정
    wire [NUM_CU * DATA_WIDTH-1:0] CU_out;
    wire valid_Bconv_out;

    // FSM 상태와 카운터 값을 모니터링하기 위한 wire
    wire [1:0] current_state_tb = dut.current_state;
    wire [4:0] counter_tb = dut.counter_1; // STEP1 카운터 모니터링

    // DUT (Device Under Test) 인스턴스화
    Bconv #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_CU(NUM_CU) // ADDED: NUM_CU 파라미터 전달
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_Bconv(start_Bconv),
        .level_in(level_in),
        .level_out(level_out),
        .coeff(coeff),
        .param(param),
        .q_in(q_in),
        .ratio_precomp(ratio_precomp),
        .CU_out(CU_out),
        .valid_Bconv_out(valid_Bconv_out)
    );

    // Clock 생성
    always #(CLK_PERIOD/2) clk = ~clk;

    // FSM 상태를 문자열로 변환해주는 함수
    function [23:0] state_to_string;
        input [1:0] state;
        begin
            case (state)
                2'b00: state_to_string = "IDLE";
                2'b01: state_to_string = "STEP1";
                2'b10: state_to_string = "STEP2";
                default: state_to_string = "UNKNOWN";
            endcase
        end
    endfunction

    // 시뮬레이션 시나리오
    initial begin
		$readmemh("/home/lyj/digital/split_llm/RTL/cu_test_vectors_full/basis_q.txt", basis_q_mem);
		$readmemh("/home/lyj/digital/split_llm/RTL/cu_test_vectors_full/basis_p.txt", basis_p_mem);
		$readmemh("/home/lyj/digital/split_llm/RTL/cu_test_vectors_full/coeffs_q.txt", coeff_q_mem); // 파일명 수정 coeffs_q.txt
		$readmemh("/home/lyj/digital/split_llm/RTL/cu_test_vectors_full/q_hat_inv.txt", q_hat_inv_mem);
		$readmemh("/home/lyj/digital/split_llm/RTL/cu_test_vectors_full/q_hat_mod_p.txt", q_hat_mod_p_mem);
		$readmemh("/home/lyj/digital/split_llm/RTL/cu_test_vectors_full/shoup_z_pre_step1.txt", shoup_ratio_q_mem);
		$readmemh("/home/lyj/digital/split_llm/RTL/cu_test_vectors_full/shoup_z_pre_step2.txt", shoup_ratio_p_mem);
		$readmemh("/home/lyj/digital/split_llm/RTL/cu_test_vectors_full/step1_results.txt", step1_results_golden);
		$readmemh("/home/lyj/digital/split_llm/RTL/cu_test_vectors_full/final_conversion_results.txt", final_results_p_golden);

        // --- 초기화 및 리셋 ---
        $display("--- Simulation Start ---");
        clk = 0;
        rst_n = 1'b0;
        start_Bconv = 1'b0;
        level_in = LEVEL;
        level_out = K;
        coeff = 0;
        param = 0;
        q_in = 0;
        ratio_precomp = 0;

        #(CLK_PERIOD); // 20ns 동안 리셋 유지
        rst_n = 1'b1; // 리셋 비활성화
        $display("[%0t ns] Reset is released. FSM should be in IDLE state.", $time);
        
        #(CLK_PERIOD); // 리셋 해제 후 안정화 대기

        // --- 테스트 시나리오 1: curr_level = 12 ---
        $display("\n--- Test Case 1: Start with curr_level = 12 ---");
        
        @(posedge clk);
        start_Bconv = 1'b1; // 시작 신호 1 클럭 사이클 동안 인가
        @(posedge clk);
        start_Bconv = 1'b0;
        for (l = 0; l < NUM_COEFF/NUM_CU; l = l + 1) begin
            // --- STEP 1: Gamma 값 계산 ---
            $display("INFO: Starting Step 1: Gamma Calculation...");
            for (i = 0; i <= LEVEL; i = i + 1) begin
    			for (k = 0; k < NUM_CU; k = k + 1) begin
    			    coeff[k * DATA_WIDTH +: DATA_WIDTH] = coeff_q_mem[k + NUM_CU * l][i];
    			end
                param         = {NUM_CU{q_hat_inv_mem[i]}};
                q_in          = {NUM_CU{basis_q_mem[i]}};
                ratio_precomp = {NUM_CU{shoup_ratio_q_mem[i]}};
                @(posedge clk);
            end

    	    coeff         = 0;
    	    param         = 0;
    	    q_in          = 0;
    	    ratio_precomp = 0;

            // --- STEP 2: 최종 결과 계산 ---
            $display("INFO: Starting Step 2: Final Result Calculation...");
            for (j = 0; j < K; j = j + 1) begin
                $display("INFO: Calculating for basis_p[%0d]", j);
                for (i = 0; i <= LEVEL; i = i + 1) begin
                    param         = {NUM_CU{q_hat_mod_p_mem[j][i]}};
                    q_in          = {NUM_CU{basis_p_mem[j]}};
                    ratio_precomp = {NUM_CU{shoup_ratio_p_mem[j][i]}};

                    ////// 검증 //////
                    if ((i == 3) && (j > 0)) begin
                        for (m = 0; m < NUM_CU; m = m + 1) begin
    			            if (CU_out[m * DATA_WIDTH +: DATA_WIDTH] == final_results_p_golden[m + NUM_CU * l][j-1]) begin
    	                        $display("SUCCESS: Test for p_%0d PASSED. DUT_out: %h, Golden: %h", j, CU_out[m * DATA_WIDTH +: DATA_WIDTH], final_results_p_golden[m + NUM_CU * l][j-1]);
    	                    end else begin
    	                        $display("ERROR: Test for p_%0d FAILED. DUT_out: %h, Golden: %h", j, CU_out[m * DATA_WIDTH +: DATA_WIDTH], final_results_p_golden[m + NUM_CU * l][j-1]);
    	                        error_count = error_count + 1;
    	                    end
    			        end
    	            end
                    ////////////////

                    if ((j==(K-1)) && (i==LEVEL)) begin
                        start_Bconv = 1'b1;
                    end
                    @(posedge clk); // 데이터 공급 후 1클럭 대기
                end
                
            end

            param         = 0;
            q_in          = 0;
            ratio_precomp = 0;

            start_Bconv = 1'b0;

            // start_Bconv <= 1'b1; // 시작 신호 1 클럭 사이클 동안 인가
            // @(posedge clk);
            // start_Bconv <= 1'b0;
        end

	    @(posedge clk);
	    @(posedge clk);
	    @(posedge clk);
	    @(posedge clk);
	    @(posedge clk);
	    @(posedge clk);
        

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

    integer n, s;
    initial begin
        #(958.1);
        for (s = 0; s < NUM_COEFF/NUM_CU; s = s + 1) begin
            for (n = 0; n < NUM_CU; n = n + 1) begin
    	        if (CU_out[n * DATA_WIDTH +: DATA_WIDTH] == final_results_p_golden[n + NUM_CU * s][j-1]) begin
    	            $display("SUCCESS: Test for p_%0d PASSED. DUT_out: %h, Golden: %h", j, CU_out[n * DATA_WIDTH +: DATA_WIDTH], final_results_p_golden[n + NUM_CU * s][K-1]);
    	        end else begin
    	            $display("ERROR: Test for p_%0d FAILED. DUT_out: %h, Golden: %h", j, CU_out[n * DATA_WIDTH +: DATA_WIDTH], final_results_p_golden[n + NUM_CU * s][K-1]);
    	            error_count = error_count + 1;
    	        end
    	    end
            #(936);
        end
    end


endmodule

























// `timescale 1ns / 1ps

// module tb_Bconv;

//     // 파라미터 선언
//     parameter DATA_WIDTH = 58;
// 	localparam CLK_PERIOD = 4;  // Clock period in ns
// 	localparam LEVEL      = 8; // Basis Q size = LEVEL + 1 = 13
// 	localparam K          = 11; // Basis P size

//     // 테스트벤치 신호 선언 (DUT의 입력은 reg, 출력은 wire)
//     // Inputs
//     reg clk;
//     reg rst_n;
//     reg start_Bconv;
//     reg [4:0] level_in;
//     reg [4:0] level_out;
//     reg [DATA_WIDTH-1:0] coeff;
//     reg [DATA_WIDTH-1:0] param;
//     reg [DATA_WIDTH-1:0] q_in;
//     reg [DATA_WIDTH-1:0] ratio_precomp;
	
// 	reg [DATA_WIDTH-1:0] basis_q_mem [0:LEVEL];
// 	reg [DATA_WIDTH-1:0] basis_p_mem [0:K-1];
// 	reg [DATA_WIDTH-1:0] coeff_q_mem [0:LEVEL];
// 	reg [DATA_WIDTH-1:0] q_hat_inv_mem [0:LEVEL];
// 	reg [DATA_WIDTH-1:0] q_hat_mod_p_mem [0:K-1][0:LEVEL];
// 	reg [DATA_WIDTH-1:0] shoup_ratio_q_mem [0:LEVEL];
// 	reg [DATA_WIDTH-1:0] shoup_ratio_p_mem [0:K-1][0:LEVEL];
// 	reg [DATA_WIDTH-1:0] step1_results_golden [0:LEVEL];
// 	reg [DATA_WIDTH-1:0] final_results_p_golden [0:K-1];

// 	integer i, j;
// 	integer error_count;

//     // Outputs
//     wire [DATA_WIDTH-1:0] CU_out;
//     wire valid_Bconv_out;

//     // FSM 상태와 카운터 값을 모니터링하기 위한 wire
//     wire [1:0] current_state_tb = dut.current_state;
//     wire [4:0] counter_tb = dut.counter_1;

//     // DUT (Device Under Test) 인스턴스화
//     Bconv #(
//         .DATA_WIDTH(DATA_WIDTH)
//     ) dut (
//         .clk(clk),
//         .rst_n(rst_n),
//         .start_Bconv(start_Bconv),
//         .level_in(level_in),
//         .level_out(level_out),
//         .coeff(coeff),
//         .param(param),
//         .q_in(q_in),
//         .ratio_precomp(ratio_precomp),
//         .CU_out(CU_out),
//         .valid_Bconv_out(valid_Bconv_out)
//     );

//     always #(CLK_PERIOD/2) clk = ~clk;

//     // FSM 상태를 문자열로 변환해주는 함수 (가독성 향상)
//     function [23:0] state_to_string;
//         input [1:0] state;
//         begin
//             case (state)
//                 2'b00: state_to_string = "IDLE";
//                 2'b01: state_to_string = "STEP1";
//                 2'b10: state_to_string = "STEP2";
//                 default: state_to_string = "UNKNOWN";
//             endcase
//         end
//     endfunction

//     // 2. 시뮬레이션 시나리오 (Stimulus)
//     initial begin
// 		$readmemh("../cu_test_vectors/basis_q.txt", basis_q_mem);
// 		$readmemh("../cu_test_vectors/basis_p.txt", basis_p_mem);
// 		$readmemh("../cu_test_vectors/coeff_q.txt", coeff_q_mem);
// 		$readmemh("../cu_test_vectors/q_hat_inv.txt", q_hat_inv_mem);
// 		$readmemh("../cu_test_vectors/q_hat_mod_p.txt", q_hat_mod_p_mem);
// 		$readmemh("../cu_test_vectors/shoup_z_pre_step1.txt", shoup_ratio_q_mem);
// 		$readmemh("../cu_test_vectors/shoup_z_pre_step2.txt", shoup_ratio_p_mem);
// 		$readmemh("../cu_test_vectors/step1_results.txt", step1_results_golden);
// 		$readmemh("../cu_test_vectors/final_conversion_results.txt", final_results_p_golden);
		
//         // --- 초기화 및 리셋 ---
//         $display("--- Simulation Start ---");
//     	clk = 0;
//         rst_n = 1'b0; // 리셋 활성화 (active-low)
//         start_Bconv = 1'b0;
//         level_in = LEVEL;
//         level_out = K;
//         coeff = 58'd0;
//         param = 58'd0;
//         q_in = 58'd0;
//         ratio_precomp = 58'd0;
        
//         #(CLK_PERIOD); // 20ns 동안 리셋 유지
//         rst_n = 1'b1; // 리셋 비활성화
//         $display("[%0t ns] Reset is released. FSM should be in IDLE state.", $time);
        
//         #(CLK_PERIOD); // 리셋 해제 후 안정화 대기

//         // --- 테스트 시나리오 1: curr_level = 12 ---
//         $display("\n--- Test Case 1: Start with curr_level = 12 ---");
//         // curr_level = 5'd12;
        
//         @(posedge clk);
//         start_Bconv = 1'b1; // 시작 신호 1 클럭 사이클 동안 인가
//         $display("[%0t ns] start_Bconv asserted. FSM should go to STEP1.", $time);

//         @(posedge clk);
//         start_Bconv = 1'b0;

//         // -----------------------------------------------------------------
// 	    // STEP 1: Calculate Gamma values and store in DUT's internal buffer
// 	    // -----------------------------------------------------------------
// 	    $display("INFO: Starting Step 1: Gamma Calculation...");

// 	    for (i = 0; i <= LEVEL; i = i + 1) begin
// 	        coeff         = coeff_q_mem[i];
// 	        param         = q_hat_inv_mem[i];
// 	        q_in          = basis_q_mem[i];
// 	        ratio_precomp = shoup_ratio_q_mem[i];
// 	        @(posedge clk);
// 	    end
	
// 	    coeff         = 0;
// 	    param         = 0;
// 	    q_in          = 0;
// 	    ratio_precomp = 0;
	
// 	    // -----------------------------------------------------------------
// 	    // STEP 2: Calculate final results for each p_j in Basis P
// 	    // -----------------------------------------------------------------
// 	    $display("INFO: Starting Step 2: Final Result Calculation...");

// 	    for (j = 0; j < K; j = j + 1) begin
		
// 	        $display("INFO: Calculating for basis_p[%0d] = %h", j, basis_p_mem[j]);

// 	        for (i = 0; i <= LEVEL; i = i + 1) begin
// 	            param         = q_hat_mod_p_mem[j][i];
// 	            q_in          = basis_p_mem[j];
// 	            ratio_precomp = shoup_ratio_p_mem[j][i];
// 	            // -------------------------------------------------------------
// 	            // Verification
// 	            // -------------------------------------------------------------
// 	            if ((i == 3) && (j > 0)) begin
// 	                if (CU_out === final_results_p_golden[j - 1]) begin
// 	                    $display("SUCCESS: Test for p_%0d PASSED. DUT_out: %h, Golden: %h", j, CU_out, final_results_p_golden[j]);
// 	                end else begin
// 	                    $display("ERROR: Test for p_%0d FAILED. DUT_out: %h, Golden: %h", j, CU_out, final_results_p_golden[j]);
// 	                    error_count = error_count + 1;
// 	                end
// 	            end
// 	            @(posedge clk);
// 	        end
	
// 	    end

// 	    @(posedge clk);
// 	    q_in = 0;
// 	    param         = 0;
// 	    ratio_precomp = 0;

// 	    @(posedge clk);
// 	    @(posedge clk);
// 	    @(posedge clk);
	
// 	    if (CU_out === final_results_p_golden[16]) begin
// 	        $display("SUCCESS: Test for p_%0d PASSED. DUT_out: %h, Golden: %h", 17, CU_out, final_results_p_golden[16]);
// 	    end else begin
// 	        $display("ERROR: Test for p_%0d FAILED. DUT_out: %h, Golden: %h", 17, CU_out, final_results_p_golden[16]);
// 	        error_count = error_count + 1;
// 	    end
// 	    @(posedge clk);
// 	    @(posedge clk);

// 	    for (i = 0; i <= LEVEL; i = i + 1) begin
// 	        if (dut.CU_0.buffer[i] === step1_results_golden[i]) begin
// 	            $display("SUCCESS: Test for gamma_%0d PASSED. DUT_out: %h, Golden: %h", i, dut.CU_0.buffer[i], step1_results_golden[i]);
// 	        end else begin
// 	            $display("ERROR: Test for gamma_%0d FAILED. DUT_out: %h, Golden: %h", i, dut.CU_0.buffer[i], step1_results_golden[i]);
// 	            error_count = error_count + 1;
// 	        end
// 	    end

// 	    $display("INFO: Step 1 finished. All gamma values are now in DUT buffer.");

// 	    // -----------------------------------------------------------------
// 	    // Final Report
// 	    // -----------------------------------------------------------------
// 	    if (error_count == 0) begin
// 	        $display("=====================================================");
// 	        $display("======= ALL TESTS PASSED! Congratulations! =======");
// 	        $display("=====================================================");
// 	    end else begin
// 	        $display("=====================================================");
// 	        $display("======= SIMULATION FAILED with %0d errors. =======", error_count);
// 	        $display("=====================================================");
// 	    end

// 	    $stop;
//     end

//     // 3. 모니터링
//     initial begin
//         // 시뮬레이션 중 주요 신호 값들을 클럭마다 출력
//         $monitor("[%0t ns] rst_n=%b, start=%b | State: %s (%b) | Counter: %d | curr_level: %d",
//                  $time, rst_n, start_Bconv, state_to_string(current_state_tb), current_state_tb, counter_tb, level_in);
//     end

// endmodule