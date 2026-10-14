`timescale 1ns/1ps
`default_nettype none

module modular_add_tb;

    // =========================================================================
    // 파라미터 및 신호 선언
    // =========================================================================
    
    // DUT 및 테스트벡터 생성 스크립트와 동일한 WORD_WIDTH 사용
    parameter integer WORD_WIDTH = 60;
    
    // DUT 입력 (reg)
    reg                      clk;
    reg                      rst_n;
    reg                      valid_in;
    reg [WORD_WIDTH-1:0]     A;
    reg [WORD_WIDTH-1:0]     B;
    reg [WORD_WIDTH-1:0]     q;

    // DUT 출력 (wire)
    wire                     valid_out;
    wire [WORD_WIDTH-1:0]    result;

    // 테스트벡터 파일을 읽기 위한 변수
    reg [WORD_WIDTH-1:0]     a_vec;
    reg [WORD_WIDTH-1:0]     b_vec;
    reg [WORD_WIDTH-1:0]     q_vec;
    reg [WORD_WIDTH-1:0]     expected_result;
    reg [WORD_WIDTH-1:0]     expected_result_d;
    
    integer                  vector_file; // 파일 핸들러
    integer                  error_count;
    integer                  vector_count;


    // =========================================================================
    // DUT (Device Under Test) 인스턴스화
    // =========================================================================
    modular_add #(
        .WORD_WIDTH(WORD_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .A(A),
        .B(B),
        .q(q),
        .valid_out(valid_out),
        .result(result)
    );


    // =========================================================================
    // 클럭 생성
    // =========================================================================
    initial begin
        clk = 1;
    end
    always #5 clk = ~clk; // 10ns 주기 (100MHz) 클럭


    // =========================================================================
    // 메인 테스트 로직
    // =========================================================================
    initial begin
        // --- 1. 초기화 및 리셋 ---
        rst_n = 1'b0; // 리셋 활성화
        valid_in = 1'b0;
        A = 0;
        B = 0;
        q = 0;
        error_count = 0;
        vector_count = 0;
        
        
        @(posedge clk);
        
        @(posedge clk);
         // 2 클럭 사이클 동안 리셋 유지
        rst_n = 1'b1; // 리셋 비활성화
        @(posedge clk);

        // --- 2. 테스트벡터 파일 열기 ---
        vector_file = $fopen("../add_test_vectors/mod_add_vectors_fixed_q.txt", "r");
        if (vector_file == 0) begin
            $display("ERROR: Cannot open vector file 'mod_add_vectors_fixed_q.txt'");
            $finish;
        end

        // --- 3. 파일 읽기 및 DUT 검증 루프 ---
        // 파일의 끝(EOF)에 도달할 때까지 반복
        while (!$feof(vector_file)) begin
            // 파일에서 한 줄을 "A B q Result" 형식의 16진수(%h)로 읽어옴
            // 파일 포맷과 정확히 일치해야 함
            if ($fscanf(vector_file, "%h %h %h %h\n", a_vec, b_vec, q_vec, expected_result) == 4) begin
                vector_count = vector_count + 1;
                
                // DUT에 입력 인가
                A = a_vec;
                B = b_vec;
                q = q_vec;
                valid_in = 1'b1;

                // DUT의 latency는 1 사이클이므로, valid_out을 기다림
                // 여기서는 간단히 1클럭을 기다림
                @(posedge clk);
                expected_result_d <= expected_result;
                
                // 결과 비교
                if (valid_out && (result !== expected_result_d)) begin
                    error_count = error_count + 1;
                    $display("=================================================");
                    $display("ERROR: Vector %0d - Mismatch!", vector_count);
                    $display("  Inputs:  A=0x%h, B=0x%h, q=0x%h", A, B, q);
                    $display("  DUT Result:    0x%h", result);
                    $display("  Expected Result: 0x%h", expected_result_d);
                    $display("=================================================");
                end
            end
        end
        
                @(posedge clk);
                valid_in = 1'b0; // 1클럭 동안만 valid 신호 인가

        // --- 4. 테스트 종료 ---
        $fclose(vector_file);

        if (error_count == 0) begin
            $display("=================================================");
            $display("✅ SUCCESS: All %0d vectors passed!", vector_count);
            $display("=================================================");
        end else begin
            $display("=================================================");
            $display("❌ FAILURE: %0d out of %0d vectors failed.", error_count, vector_count);
            $display("=================================================");
        end

        $stop; // 시뮬레이션 종료
    end

endmodule

`default_nettype wire