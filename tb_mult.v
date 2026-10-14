`timescale 1ns/1ps
`default_nettype none

module barrett_mult_tb_preload;

    // =========================================================================
    // 파라미터 및 신호 선언
    // =========================================================================
    
    parameter integer WORD_WIDTH = 60;
    // 📌 중요: 이 파라미터는 테스트벡터 파일의 라인 수와 정확히 일치해야 합니다.
    parameter integer NUM_VECTORS = 256; 
    
    // DUT 입출력
    reg                      clk, rst_n, valid_in;
    reg [WORD_WIDTH-1:0]     A, B, q;
    reg [2*WORD_WIDTH-1:0]   mu;
    wire                     valid_out;
    wire [WORD_WIDTH-1:0]    result;

    // --- 데이터 저장을 위한 배열(메모리) 선언 ---
    reg [WORD_WIDTH-1:0]     a_array        [0:NUM_VECTORS-1];
    reg [WORD_WIDTH-1:0]     b_array        [0:NUM_VECTORS-1];
    reg [WORD_WIDTH-1:0]     q_array        [0:NUM_VECTORS-1];
    reg [2*WORD_WIDTH-1:0]   mu_array       [0:NUM_VECTORS-1];
    reg [WORD_WIDTH-1:0]     expected_array [0:NUM_VECTORS-1];
    reg [WORD_WIDTH-1:0]     expected;
    
    integer                  i; // 루프 카운터
    integer                  vector_file, error_count, vector_count;

    // =========================================================================
    // DUT 인스턴스화
    // =========================================================================
    barrett_mult #(.WORD_WIDTH(WORD_WIDTH)) dut (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .A(A), .B(B), .q(q), .mu(mu),
        .valid_out(valid_out), .result(result)
    );

    // =========================================================================
    // 클럭 생성
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // 메인 테스트 로직
    // =========================================================================
    initial begin
        // --- 1. 테스트벡터 파일 열고 모든 데이터를 배열에 미리 저장 ---
        vector_file = $fopen("../add_test_vectors/barrett_mult_vectors.txt", "r");
        if (vector_file == 0) begin
            $display("ERROR: Cannot open vector file.");
            $finish;
        end
        
        $display("INFO: Pre-loading %0d vectors from file...", NUM_VECTORS);
        for (i = 0; i < NUM_VECTORS; i = i + 1) begin
            $fscanf(vector_file, "%h %h %h %h %h\n", 
                a_array[i], b_array[i], q_array[i], mu_array[i], expected_array[i]);
        end
        $fclose(vector_file);
        $display("INFO: Pre-loading complete.");

        // --- 2. 초기화 및 리셋 ---
        rst_n = 1'b0;
        valid_in = 1'b0;
        A = 0; B = 0; q = 0; mu = 0;
        error_count = 0;
        
        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // --- 3. 배열에 저장된 값으로 DUT 검증 실행 ---
        for (vector_count = 0; vector_count < NUM_VECTORS; vector_count = vector_count + 1) begin
            // 배열에서 값을 읽어와 DUT에 인가
            A = a_array[vector_count];
            B = b_array[vector_count];
            q = q_array[vector_count];
            mu = mu_array[vector_count];
            
            valid_in = 1'b1;

            // 4-사이클 지연 시간 처리
            // while (!valid_out) begin
            @(posedge clk);
            // end
            
            // 결과 비교
			if (vector_count > 2) begin
				expected <= expected_array[vector_count-3];
            	if (result !== expected) begin
            	    error_count = error_count + 1;
            	    $display("ERROR: Vector %0d - Mismatch!", vector_count + 1);
            	    $display("result: ", result);
            	    $display("expected result: ", expected);
            	    // ... (에러 메시지 출력)
					$display("=================================================");
    				$display("ERROR: Vector %0d - Mismatch!", vector_count + 1);
    				// 📌 실패 시 모든 입력값을 자세히 출력
    				$display("  Inputs:");
    				$display("    A = 0x%h (%0d)", a_array[vector_count-4], a_array[vector_count-4]);
    				$display("    B = 0x%h (%0d)", b_array[vector_count-4], b_array[vector_count-4]);
    				$display("    q = 0x%h (%0d)", q_array[vector_count-4], q_array[vector_count-4]);
    				$display("   mu = 0x%h", mu_array[vector_count-4]);
    				$display("  Results:");
    				$display("    DUT Result      = 0x%h (%0d)", result, result);
    				$display("    Expected Result = 0x%h (%0d)", expected, expected);
    				$display("=================================================");
            	end
			end
        end

        @(posedge clk);
        valid_in = 1'b0;

        // --- 4. 테스트 종료 ---
        if (error_count == 0) begin
            $display("SUCCESS: All %0d vectors passed!", NUM_VECTORS);
        end else begin
            $display("FAILURE: %0d out of %0d vectors failed.", error_count, NUM_VECTORS);
        end

        $stop;
    end

endmodule