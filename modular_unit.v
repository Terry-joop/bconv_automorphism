//=============================================================================
// 통합 모듈러 연산 유닛 (Top Module)
// mode
// 000:idle, 
// 001:add, 
// 010:sub, 
// 011:mult, 
// 100:rot, 
// 101:addrot
//=============================================================================
module modular_unit #(
    parameter integer WORD_WIDTH = 60 // 데이터 비트 폭 파라미터
)(
    input  wire                      clk,      // 클럭
    input  wire                      rst_n,    // 리셋 (active low)

    // --- Control & Data Inputs ---
    input  wire                      valid_in, // 입력 유효 신호
    input  wire                      s_in,     // 입력 유효 신호
    input  wire [2:0]                mode,     // 연산 모드
    input  wire [WORD_WIDTH-1:0]     A,        // 피연산자 A
    input  wire [WORD_WIDTH-1:0]     B,        // 피연산자 B
    input  wire [WORD_WIDTH-1:0]     q,        // 모듈러스 q
    input  wire [2*WORD_WIDTH-1:0]   mu,       // Barrett 곱셈용 상수
    input  wire [5:0]                q_width,

    // --- Control & Data Outputs ---
    output wire                      valid_out,// 출력 유효 신호
    output wire [WORD_WIDTH-1:0]     result   // 연산 결과
);

    localparam IDLE   = 3'b000;
    localparam ADD    = 3'b001;
    localparam SUB    = 3'b010;
    localparam MULT   = 3'b011;
    localparam ROT    = 3'b100;
    localparam ADDROT = 3'b101;

    //-------------------------------------------------------------------------
    // 내부 신호 선언
    //-------------------------------------------------------------------------
    // 각 자식 모듈로 전달될 valid 신호
    wire add_valid_in;
    wire sub_valid_in;
    wire mult_valid_in;
    reg  addrot_valid_in;
    reg  addrot_valid_in_d;
    reg  addrot_sub_valid_in;

    // 각 자식 모듈의 결과 및 valid 출력
    wire [WORD_WIDTH-1:0] add_result;
    wire [WORD_WIDTH-1:0] add_result_temp;
    wire [WORD_WIDTH-1:0] add_result_1;
    reg  [WORD_WIDTH-1:0] add_result_2;
    wire [WORD_WIDTH-1:0] add_out_sub_in;
    wire [WORD_WIDTH-1:0] sub_result;
    wire [WORD_WIDTH-1:0] sub_result_temp;
    wire [WORD_WIDTH-1:0] mult_result;

    wire add_valid_out;
    wire sub_valid_out;
    wire mult_valid_out;
    wire valid_out_temp;

    reg [2:0] mode_d;

    //-------------------------------------------------------------------------
    // 제어 로직: mode에 따라 활성화할 모듈 선택
    //-------------------------------------------------------------------------
    assign add_valid_in  = ((mode == ADD) || (mode == ADDROT)) && valid_in;
    assign sub_valid_in  = (((mode == SUB) || (mode == ROT)) && valid_in) || addrot_sub_valid_in;
    assign mult_valid_in = (mode == MULT) && valid_in;

    wire s;
    reg s_d, s_dd;
    assign s = (mode == ADD) ? 0 : s_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addrot_valid_in <= 0;
            addrot_valid_in_d <= 0;
            addrot_sub_valid_in <= 0;
            s_d <= 0;
            s_dd <= 0;
            mode_d <= 0;
        end else begin
            if ((mode == ADDROT)) begin
                addrot_valid_in <= 1;
            end else begin
                addrot_valid_in <= 0;
            end
            if ((mode == ADDROT) && (s == 1)) begin
                addrot_sub_valid_in <= 1;
            end else begin
                addrot_sub_valid_in <= 0;
            end
            addrot_valid_in_d <= addrot_valid_in;
            s_d <= s;
            s_dd <= s_d && (mode_d == ADDROT);
            mode_d <= mode;
        end
    end

    //-------------------------------------------------------------------------
    // 자식 모듈 인스턴스화
    //-------------------------------------------------------------------------
    // 1. 모듈러 덧셈기
    modular_add #( .WORD_WIDTH(WORD_WIDTH) ) u_modular_add (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (add_valid_in),
        .A          (A),
        .B          (B),
        .q          (q),
        .valid_out  (add_valid_out),
        .result     (add_result_temp)
    );

    assign add_result_1 = (s_d == 0) ? add_result_temp : {WORD_WIDTH{1'b0}};
    assign add_out_sub_in = (s_d == 1) ? add_result_temp : {WORD_WIDTH{1'b0}};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            add_result_2 <= 0;
        end else begin
            if (addrot_valid_in && !s_d) begin
                add_result_2 <= add_result_1; 
            end else begin 
                add_result_2 <= 0;
            end
        end
    end
    assign add_result = (mode_d == ADD) ? add_result_1 : 
                        addrot_valid_in_d ? add_result_2 : {WORD_WIDTH{1'b0}};

    // 2. 모듈러 뺄셈기
    wire [WORD_WIDTH-1:0] sub_in_A, sub_in_B;
    reg [WORD_WIDTH-1:0] sub_in_B_d;
    assign sub_in_A = (mode == SUB) ? A : 
                      ((mode == ROT) || addrot_sub_valid_in) ? q : {WORD_WIDTH{1'b0}};
    assign sub_in_B = ((mode == SUB) || (mode == ROT)) ? B : 
                      (addrot_sub_valid_in) ? add_out_sub_in : {WORD_WIDTH{1'b0}};

    modular_sub #( .WORD_WIDTH(WORD_WIDTH) ) u_modular_sub (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (sub_valid_in),
        .A          (sub_in_A),
        .B          (sub_in_B),
        .q          (q),
        .valid_out  (sub_valid_out),
        .result     (sub_result_temp)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sub_in_B_d <= 0;
        end else begin
            if (mode == ROT) begin
                sub_in_B_d <= sub_in_B; 
            end else begin 
                sub_in_B_d <= 0;
            end
        end
    end

    assign sub_result = (mode_d == SUB) ? sub_result_temp :
                        (mode_d == ROT) ? ((s_d) ? sub_result_temp : sub_in_B_d) :
                        (s_dd) ? sub_result_temp : sub_in_B_d;

    // 3. 모듈러 곱셈기 (Barrett)
    barrett_mult #( .WORD_WIDTH(WORD_WIDTH) ) u_barrett_mult (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (mult_valid_in),
        .A          (A),
        .B          (B),
        .q          (q),
        .mu         (mu),
        .q_width    (q_width),
        .valid_out  (mult_valid_out),
        .result     (mult_result)
    );


    // 최종 출력 할당
    // assign result = (add_valid_out || addrot_valid_in_d)  ? add_result :
    //                 (sub_valid_out || s_dd)  ? sub_result :
    //                 mult_valid_out ? mult_result : {WORD_WIDTH{1'b0}};
    assign result = s_dd ? sub_result :
                    addrot_valid_in_d ? add_result :
                    add_valid_out ? add_result :
                    sub_valid_out ? sub_result :
                    mult_valid_out ? mult_result : {WORD_WIDTH{1'b0}};
    assign valid_out_temp = add_valid_out | sub_valid_out | mult_valid_out;
   
    assign valid_out = ((mode == ADDROT) || addrot_valid_in_d) ? addrot_valid_in_d : valid_out_temp;
    // always @(*) begin
    //         valid_reg = add_valid_out | sub_valid_out | mult_valid_out;

    //         if (add_valid_out) begin
    //             result_reg = add_result;
    //         end else if (sub_valid_out) begin
    //             result_reg = sub_result;
    //         end else if (mult_valid_out) begin
    //             result_reg = mult_result;
    //         end else begin
    //             result_reg <= {WORD_WIDTH{1'b0}};
    //         end
    //     // end
    // end

    // // 최종 출력 할당
    // assign result    = result_reg;
    // assign valid_out = valid_reg;


endmodule

