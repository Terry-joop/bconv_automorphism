`timescale 1ns/1ps
`default_nettype none

module modular_unit_tb_separate_preload;

    // =========================================================================
    // 파라미터 및 신호 선언
    // =========================================================================
    parameter integer WORD_WIDTH = 60;
    
    // 각 테스트벡터 파일의 라인 수
    parameter integer NUM_ADD_VECTORS  = 256;
    parameter integer NUM_SUB_VECTORS  = 256;
    parameter integer NUM_MULT_VECTORS = 256;

    // DUT 입출력
    reg                      clk, rst_n, valid_in, s_in;
    reg [2:0]                mode;
    reg [WORD_WIDTH-1:0]     A, B, q;
    reg [2*WORD_WIDTH-1:0]   mu;
    wire                     valid_out;
    wire [WORD_WIDTH-1:0]    result;

    // --- 📌 연산별로 분리된 메모리 배열 선언 ---
    // 덧셈용 배열
    reg [WORD_WIDTH-1:0] add_a_array[0:NUM_ADD_VECTORS-1], add_b_array[0:NUM_ADD_VECTORS-1], add_q_array[0:NUM_ADD_VECTORS-1], add_expected_array[0:NUM_ADD_VECTORS-1];
    
    // 뺄셈용 배열
    reg [WORD_WIDTH-1:0] sub_a_array[0:NUM_SUB_VECTORS-1], sub_b_array[0:NUM_SUB_VECTORS-1], sub_q_array[0:NUM_SUB_VECTORS-1], sub_expected_array[0:NUM_SUB_VECTORS-1];

    // 곱셈용 배열
    reg [WORD_WIDTH-1:0]   mult_a_array[0:NUM_MULT_VECTORS-1], mult_b_array[0:NUM_MULT_VECTORS-1], mult_q_array[0:NUM_MULT_VECTORS-1], mult_expected_array[0:NUM_MULT_VECTORS-1];
    reg [2*WORD_WIDTH-1:0] mult_mu_array[0:NUM_MULT_VECTORS-1];
	
    reg [WORD_WIDTH-1:0]     expected_result_d;
    
    integer file, error_count, total_vectors, vec_idx;

    // =========================================================================
    // DUT 인스턴스화
    // =========================================================================
    modular_unit #(.WORD_WIDTH(WORD_WIDTH)) dut (
        .clk(clk), 
        .rst_n(rst_n), 
        .valid_in(valid_in), 
        .s_in(s_in), 
        .mode(mode),
        .A(A), 
        .B(B), 
        .q(q), 
        .mu(mu),
        .valid_out(valid_out), 
        .result(result)
    );

    // =========================================================================
    // 클럭 생성
    // =========================================================================
    initial clk = 1;
    always #5 clk = ~clk;
	
	integer scan_count; 

    reg s_in_d, s_in_dd;

    // =========================================================================
    // 메인 테스트 로직
    // =========================================================================
    initial begin
        error_count = 0;
        total_vectors = 0;

        // --- 1. 각 파일의 데이터를 해당하는 배열에 미리 저장 ---
        $display("--- Starting Pre-loading of All Test Vectors ---");
        
        file = $fopen("../add_test_vectors/mod_add_vectors_fixed_q.txt", "r");
        for (vec_idx = 0; vec_idx < NUM_ADD_VECTORS; vec_idx = vec_idx + 1)
            scan_count =  $fscanf(file, "%h %h %h %h\n", add_a_array[vec_idx], add_b_array[vec_idx], add_q_array[vec_idx], add_expected_array[vec_idx]);
        $fclose(file);
        $display("INFO: Loaded %0d addition vectors into dedicated arrays.", NUM_ADD_VECTORS);

        file = $fopen("../add_test_vectors/mod_sub_vectors_fixed_q.txt", "r");
        for (vec_idx = 0; vec_idx < NUM_SUB_VECTORS; vec_idx = vec_idx + 1)
            scan_count =  $fscanf(file, "%h %h %h %h\n", sub_a_array[vec_idx], sub_b_array[vec_idx], sub_q_array[vec_idx], sub_expected_array[vec_idx]);
        $fclose(file);
        $display("INFO: Loaded %0d subtraction vectors into dedicated arrays.", NUM_SUB_VECTORS);

        file = $fopen("../add_test_vectors/barrett_mult_vectors.txt", "r");
        for (vec_idx = 0; vec_idx < NUM_MULT_VECTORS; vec_idx = vec_idx + 1)
            scan_count =  $fscanf(file, "%h %h %h %h %h\n", mult_a_array[vec_idx], mult_b_array[vec_idx], mult_q_array[vec_idx], mult_mu_array[vec_idx], mult_expected_array[vec_idx]);
        $fclose(file);
        $display("INFO: Loaded %0d multiplication vectors into dedicated arrays.", NUM_MULT_VECTORS);
        $display("--- Pre-loading Complete ---");
        
        // --- 2. 초기화 및 리셋 ---
        rst_n = 1'b0; 
        valid_in = 1'b0; 
        s_in = 1'b0;
        s_in_d = 1'b0;
        s_in_dd = 1'b0;
        mode = 2'b00; 
        A = 0; 
        B = 0; 
        q = 0; 
        mu = 0;

        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;

        @(posedge clk);
        @(posedge clk);

        // --- 3. 각 연산에 대해 분리된 테스트 실행 ---
        // 3-1. rot 테스트
        $display("\n--- Starting Rot Test ---");
        for (vec_idx = 0; vec_idx < NUM_ADD_VECTORS; vec_idx = vec_idx + 1) begin
            mode = 3'b100;
            // s_in = 1'b0;
            A = add_a_array[vec_idx]; 
			B = add_b_array[vec_idx]; 
			q = add_q_array[vec_idx];
            valid_in = 1'b1; 

            if ((vec_idx % 4) == 3) begin 
                s_in = 1'b1;
            end else begin 
                s_in = 1'b0;
            end
                
            s_in_d <= s_in;
            
			@(posedge clk); 
            if (s_in_d) begin
                expected_result_d <= q - add_b_array[vec_idx];
            end else begin
                expected_result_d <= B;
            end 
            // expected_result_d <= B;
            // expected_result_d <= q - add_b_array[vec_idx];
            if (vec_idx > 0) begin
                if (result !== expected_result_d) begin
                    error_count = error_count + 1;
                    $display("=================================================");
                    $display("ERROR: Vector %0d - Mismatch!", vec_idx);
                    $display("  Inputs:  A=0x%h, B=0x%h, q=0x%h", A, B, q);
                    $display("  DUT Result:    0x%h", result);
                    $display("  Expected Result: 0x%h", expected_result_d);
                    $display("=================================================");
                end
            end
        end
		valid_in = 1'b0;
        s_in = 1'b0;
        mode = 2'b00;
        A = 0; 
		B = 0; 
		// q = 0;

        total_vectors = total_vectors + NUM_ADD_VECTORS;
		
        if (error_count == 0) begin
            $display("\n✅ SUCCESS add test", total_vectors);
        end else begin
            $display("\n❌ FAILURE: %0d out of %0d vectors failed.", error_count, total_vectors);
        end

        
		@(posedge clk); 
		@(posedge clk); 
		@(posedge clk); 
		@(posedge clk); 




        // 3-1. addrot 테스트
        $display("\n--- Starting AddRot Test ---");
        for (vec_idx = 0; vec_idx < NUM_ADD_VECTORS; vec_idx = vec_idx + 1) begin
            mode = 3'b101;
            A = add_a_array[vec_idx]; 
			B = add_b_array[vec_idx]; 
			q = add_q_array[vec_idx];
            valid_in = 1'b1; 
            // s_in = 1'b1;

            if ((vec_idx % 4) == 3) begin 
                s_in = 1'b1;
            end else begin 
                s_in = 1'b0;
            end
                
            s_in_d <= s_in;
            s_in_dd <= s_in_d;
            
			@(posedge clk); 
            if (s_in_dd) begin
                expected_result_d <= q-add_expected_array[vec_idx - 1];
            end else begin
                expected_result_d <= add_expected_array[vec_idx - 1];
            end
            // expected_result_d <= q-add_expected_array[vec_idx - 1];
            // expected_result_d <= add_expected_array[vec_idx - 1];
            if (vec_idx > 1) begin
                if (result !== expected_result_d) begin
                    error_count = error_count + 1;
                    $display("=================================================");
                    $display("ERROR: Vector %0d - Mismatch!", vec_idx);
                    $display("  Inputs:  A=0x%h, B=0x%h, q=0x%h", A, B, q);
                    $display("  DUT Result:    0x%h", result);
                    $display("  Expected Result: 0x%h", expected_result_d);
                    $display("=================================================");
                end
            end
        end
		valid_in = 1'b0;
        s_in = 1'b0;
        mode = 2'b00;
        A = 0; 
		B = 0; 
		// q = 0;

        @(posedge clk); 
        expected_result_d <= q-add_expected_array[255];
        if (result !== expected_result_d) begin
            error_count = error_count + 1;
            $display("=================================================");
            $display("ERROR: Vector %0d - Mismatch!", vec_idx);
            $display("  Inputs:  A=0x%h, B=0x%h, q=0x%h", A, B, q);
            $display("  DUT Result:    0x%h", result);
            $display("  Expected Result: 0x%h", expected_result_d);
            $display("=================================================");
        end

        
        total_vectors = total_vectors + NUM_ADD_VECTORS;
		
        if (error_count == 0) begin
            $display("\n✅ SUCCESS add test", total_vectors);
        end else begin
            $display("\n❌ FAILURE: %0d out of %0d vectors failed.", error_count, total_vectors);
        end

		
		@(posedge clk); 
		@(posedge clk); 
		@(posedge clk); 
		@(posedge clk); 
        
        
        // 3-1. 덧셈 테스트
        $display("\n--- Starting Modular Addition Test ---");
        for (vec_idx = 0; vec_idx < NUM_ADD_VECTORS; vec_idx = vec_idx + 1) begin
            mode = 3'b001;
            A = add_a_array[vec_idx]; 
			B = add_b_array[vec_idx]; 
			q = add_q_array[vec_idx];
            valid_in = 1'b1; 
			
			@(posedge clk); 
            expected_result_d <= add_expected_array[vec_idx];
            if (vec_idx > 0) begin
                if (result !== expected_result_d) begin
                    error_count = error_count + 1;
                    $display("=================================================");
                    $display("ERROR: Vector %0d - Mismatch!", vec_idx);
                    $display("  Inputs:  A=0x%h, B=0x%h, q=0x%h", A, B, q);
                    $display("  DUT Result:    0x%h", result);
                    $display("  Expected Result: 0x%h", expected_result_d);
                    $display("=================================================");
                end
            end
        end
		valid_in = 1'b0;
        mode = 2'b00;
        A = 0; 
		B = 0; 
		q = 0;
        total_vectors = total_vectors + NUM_ADD_VECTORS;
		
        if (error_count == 0) begin
            $display("\n✅ SUCCESS add test", total_vectors);
        end else begin
            $display("\n❌ FAILURE: %0d out of %0d vectors failed.", error_count, total_vectors);
        end

		
		@(posedge clk); 
		@(posedge clk); 
		@(posedge clk); 
		@(posedge clk); 
        
        // 3-2. 뺄셈 테스트
        $display("\n--- Starting Modular Subtraction Test ---");
        for (vec_idx = 0; vec_idx < NUM_SUB_VECTORS; vec_idx = vec_idx + 1) begin
            mode = 3'b010;
            A = sub_a_array[vec_idx]; 
			B = sub_b_array[vec_idx]; 
			q = sub_q_array[vec_idx];
            valid_in = 1'b1; 
			@(posedge clk); 
            expected_result_d <= sub_expected_array[vec_idx];
            if (vec_idx > 0) begin
                if (result !== expected_result_d) begin
                    error_count = error_count + 1;
                    $display("=================================================");
                    $display("ERROR: Vector %0d - Mismatch!", vec_idx);
                    $display("  Inputs:  A=0x%h, B=0x%h, q=0x%h", A, B, q);
                    $display("  DUT Result:    0x%h", result);
                    $display("  Expected Result: 0x%h", expected_result_d);
                    $display("=================================================");
                end
            end
        end
		valid_in = 1'b0; 
        mode = 2'b00;
        A = 0; 
		B = 0; 
		q = 0;
		
        total_vectors = total_vectors + NUM_SUB_VECTORS;
		
        if (error_count == 0) begin
            $display("\n✅ SUCCESS sub test", total_vectors);
        end else begin
            $display("\n❌ FAILURE: %0d out of %0d vectors failed.", error_count, total_vectors);
        end
		
		@(posedge clk); 
		@(posedge clk); 
		@(posedge clk); 
		@(posedge clk); 

        // 3-3. 곱셈 테스트
        $display("\n--- Starting Barrett Multiplication Test ---");
        for (vec_idx = 0; vec_idx < NUM_MULT_VECTORS; vec_idx = vec_idx + 1) begin
            mode = 3'b011;
            A = mult_a_array[vec_idx]; 
			B = mult_b_array[vec_idx]; 
			q = mult_q_array[vec_idx]; 
			mu = mult_mu_array[vec_idx];
            valid_in = 1'b1; 

			@(posedge clk);
            if (vec_idx > 2) begin
				expected_result_d <= mult_expected_array[vec_idx-3];
            	if (result !== expected_result_d) begin
            	    error_count = error_count + 1;
					$display("=================================================");
    				$display("ERROR: Vector %0d - Mismatch!", vec_idx + 1);
    				// 📌 실패 시 모든 입력값을 자세히 출력
    				$display("  Inputs:");
    				$display("    A = %h (%d)", mult_a_array[vec_idx-4], mult_a_array[vec_idx-4]);
    				$display("    B = %h (%d)", mult_b_array[vec_idx-4], mult_b_array[vec_idx-4]);
    				$display("    q = %h (%d)", mult_q_array[vec_idx-4], mult_q_array[vec_idx-4]);
    				$display("   mu = %h", mult_mu_array[vec_idx-4]);
    				$display("  Results:");
    				$display("    DUT Result      = 0x%h (%0d)", result, result);
    				$display("    Expected Result = 0x%h (%0d)", expected_result_d, expected_result_d);
    				$display("=================================================");
            	end
			end
        end
		valid_in = 1'b0; 
        mode = 2'b00;
        A = 0; 
		B = 0; 
		q = 0;
        total_vectors = total_vectors + NUM_MULT_VECTORS;

        // --- 4. 최종 결과 요약 ---
        #100;
        if (error_count == 0) begin
            $display("\n✅ SUCCESS: All %0d vectors passed!", total_vectors);
        end else begin
            $display("\n❌ FAILURE: %0d out of %0d vectors failed.", error_count, total_vectors);
        end
        $stop;
    end

endmodule