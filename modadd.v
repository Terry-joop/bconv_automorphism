module modular_add #(
    parameter integer WORD_WIDTH = 60 // 데이터 비트 폭 파라미터
)(
    input  wire                      clk,      // 클럭
    input  wire                      rst_n,    // 리셋 (active low)

    input  wire                      valid_in, // 입력 유효 신호
    input  wire [WORD_WIDTH-1:0]     A,        // 피연산자 A
    input  wire [WORD_WIDTH-1:0]     B,        // 피연산자 B
    input  wire [WORD_WIDTH-1:0]     q,        // 모듈러스 q

    output wire                      valid_out,// 출력 유효 신호
    output wire [WORD_WIDTH-1:0]     result   // 결과 (A + B) mod q
);

    // 내부 레지스터 선언
    reg [WORD_WIDTH-1:0] result_reg;
    reg                  valid_reg;

    // A와 B의 합은 WORD_WIDTH+1 비트가 될 수 있으므로 오버플로우 방지
    wire [WORD_WIDTH:0] sum = A + B;

    // sum에서 q를 뺀 값
    wire [WORD_WIDTH:0] sum_minus_q = sum - q;

    // 동기식 로직 (Synchronous Logic)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_reg <= {WORD_WIDTH{1'b0}};
            valid_reg  <= 1'b0;
        end else begin
            if (valid_in) begin
                if (sum >= q) begin
                    result_reg <= sum_minus_q[WORD_WIDTH-1:0];
                end else begin
                    result_reg <= sum[WORD_WIDTH-1:0];
                end
                valid_reg <= 1'b1;
            end else begin
                valid_reg <= 1'b0;
                result_reg <= {WORD_WIDTH{1'b0}};
            end
        end
    end

    // 최종 출력 할당
    assign result    = result_reg;
    assign valid_out = valid_reg;

endmodule
