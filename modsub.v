module modular_sub #(
    parameter integer WORD_WIDTH = 16 // 데이터 비트 폭 파라미터
)(
    input  wire                      clk,      // 클럭
    input  wire                      rst_n,    // 리셋 (active low)

    input  wire                      valid_in, // 입력 유효 신호
    input  wire [WORD_WIDTH-1:0]     A,        // 피연산자 A
    input  wire [WORD_WIDTH-1:0]     B,        // 피연산자 B
    input  wire [WORD_WIDTH-1:0]     q,        // 모듈러스 q

    output wire                      valid_out,// 출력 유효 신호
    output wire [WORD_WIDTH-1:0]     result   // 결과 (A - B) mod q
);

    // 내부 레지스터 선언
    reg [WORD_WIDTH-1:0] result_reg;
    reg                  valid_reg;

    // A - B 계산
    wire [WORD_WIDTH-1:0] diff = A - B;
    
    wire [WORD_WIDTH:0] diff_plus_q = {1'b0, diff} + {1'b0, q};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_reg <= {WORD_WIDTH{1'b0}};
            valid_reg  <= 1'b0;
        end else if (valid_in) begin
            if (A < B) begin
                result_reg <= diff_plus_q[WORD_WIDTH-1:0];
            end else begin
                result_reg <= diff;
            end
            valid_reg <= 1'b1; 
        end else begin
            valid_reg <= 1'b0; 
        end
    end

    // 최종 출력 할당
    assign result    = result_reg;
    assign valid_out = valid_reg;

endmodule
