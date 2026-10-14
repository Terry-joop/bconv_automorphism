`timescale 1ns / 1ps

module tb_adder_tree;

    // DUT 파라미터 정의
    localparam WIDTH      = 60;
    localparam MAX_INPUTS = 13;
    localparam CLK_PERIOD = 10; // 클럭 주기 (10ns -> 100MHz)

    // DUT 연결을 위한 신호 선언
    logic                       clk;
    logic                       rst_n;
    logic                       i_valid;
    logic [WIDTH-1:0]           i_inputs [MAX_INPUTS-1:0];
    logic [3:0]                 i_input_count;
    logic [WIDTH-1:0]           i_q;
    logic                       o_valid;
    logic [WIDTH-1:0]           o_sum;

    // [수정 1] 큐(Queue) 선언 문법을 '_' 에서 '$'로 수정
    logic [WIDTH-1:0]           expected_sum_q [$]; 

    // DUT (Device Under Test) 인스턴스화
    // DUT 모듈 이름이 'adder_tree'라고 가정합니다.
    adder_tree #(
        .WIDTH(WIDTH),
        .MAX_INPUTS(MAX_INPUTS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_valid(i_valid),
        .i_inputs(i_inputs),
        .i_input_count(i_input_count),
        .i_q(i_q),
        .o_valid(o_valid),
        .o_sum(o_sum)
    );

    // 1. 클럭 생성
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // 2. 테스트 시나리오 (Stimulus)
    initial begin
        $display("------------------- Simulation Start -------------------");
        // 초기화 및 리셋
        initialize_signals();
        apply_reset();
        
        // --- 테스트 케이스 1: 최소 입력(5개) 기본 검증 ---
        run_test_case(5, 100, 1); // 5개 입력, q=100, 입력값 1,2,3,4,5
        
        // --- 테스트 케이스 2: 최대 입력(13개) 검증 ---
        run_test_case(13, 200, 10); // 13개 입력, q=200, 입력값 10,11,...,22

        // --- 테스트 케이스 3: 파이프라인 검증 (3개의 데이터를 연속으로 입력) ---
        $display("\n[Test Case 3] Pipeline Test - 3 consecutive inputs");
        i_q = 50;
        // Transaction 1
        i_input_count = 6;
        set_inputs(6, 1); // 1,2,3,4,5,6 -> sum=21
        calculate_and_push_expected(6, 1, 50); // 예상 결과: 21
        i_valid = 1'b1;
        @(posedge clk);

        // Transaction 2
        i_input_count = 7;
        set_inputs(7, 2); // 2,3,4,5,6,7,8 -> sum=35
        calculate_and_push_expected(7, 2, 50); // 예상 결과: 35
        i_valid = 1'b1;
        @(posedge clk);
        
        // Transaction 3
        i_input_count = 8;
        set_inputs(8, 3); // 3,4,5,6,7,8,9,10 -> sum=52
        calculate_and_push_expected(8, 3, 50); // 예상 결과: 2
        i_valid = 1'b1;
        @(posedge clk);

        i_valid = 1'b0; // 입력 종료
        
        // 결과가 모두 나올 때까지 대기
        wait (expected_sum_q.size() == 0);
        
        repeat(5) @(posedge clk);
        $display("-------------------- Simulation End --------------------");
        $finish;
    end
    
    // 3. 출력 검증 (Checker)
    always @(posedge clk) begin
        if (o_valid) begin
            if (expected_sum_q.size() > 0) begin
                // [수정 2] 'automatic' 키워드 추가
                automatic logic [WIDTH-1:0] expected_val = expected_sum_q.pop_front();
                if (o_sum == expected_val) begin
                    $display("[Checker] PASS! Time=%0t, Output=%d, Expected=%d", $time, o_sum, expected_val);
                end else begin
                    $error("[Checker] FAIL! Time=%0t, Output=%d, Expected=%d", $time, o_sum, expected_val);
                end
            end else begin
                $warning("[Checker] WARNING! Unexpected valid output at Time=%0t", $time);
            end
        end
    end

    // --- 테스트를 위한 Task들 ---

    // 신호 초기화 Task
    task initialize_signals();
        i_valid = 1'b0;
        i_input_count = '0;
        i_q = '0;
        foreach (i_inputs[i]) begin
            i_inputs[i] = '0;
        end
    endtask

    // 리셋 적용 Task
    task apply_reset();
        $display("Applying reset...");
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        $display("Reset released.");
    endtask

    // 입력 배열 설정 Task
    task set_inputs(input int count, input int start_val);
        for (int i = 0; i < MAX_INPUTS; i++) begin
            if (i < count)
                i_inputs[i] = start_val + i;
            else
                i_inputs[i] = '0;
        end
    endtask

    // 예상 결과 계산 및 큐에 저장 Task
    task calculate_and_push_expected(input int count, input int start_val, input logic [WIDTH-1:0] q);
        // [수정 3] 'automatic' 키워드 추가
        automatic logic [WIDTH+7:0] temp_sum = 0; 
        for (int i = 0; i < count; i++) begin
            temp_sum = temp_sum + (start_val + i);
        end
        expected_sum_q.push_back(temp_sum % q);
        $display("[Stimulus] Pushed expected value: %d", temp_sum % q);
    endtask
    
    // 단일 테스트 케이스 실행 Task
    task run_test_case(input int count, input logic [WIDTH-1:0] q, input int start_val);
        // [수정 4] 'automatic' 키워드 추가
        automatic string test_type = (count == MAX_INPUTS) ? "Max" : "Min";
        $display("\n[Test Case] %s Input Test (%0d inputs), q=%0d", test_type, count, q);
        i_q = q;
        i_input_count = count;
        set_inputs(count, start_val);
        calculate_and_push_expected(count, start_val, q);
        
        i_valid = 1'b1;
        @(posedge clk);
        i_valid = 1'b0;
        
        // 결과가 나올 때까지 대기
        wait (o_valid);
        repeat(2) @(posedge clk);
    endtask

endmodule