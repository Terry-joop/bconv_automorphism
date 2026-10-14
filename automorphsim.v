// 16x16 모듈러 곱셈기 (Synchronous, Registered I/O)
// 동작: result = (i * k) mod 2^16
module automorphism (
    // --- Ports ---
    input  wire         clk,      
    input  wire         rst_n,    
    input  wire [15:0]  i_in,       
    input  wire [15:0]  k_in,       
    output wire  [15:0]  result_out  
);

    // reg [15:0] i_reg;
    // reg [15:0] k_reg;
    reg [15:0] result_reg;

    wire [31:0] product;

    assign product = i_in * k_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // i_reg      <= 16'b0;
            // k_reg      <= 16'b0;
            result_reg <= 16'b0;
        end else begin
            // i_reg <= i_in;
            // k_reg <= k_in;
            result_reg <= product[15:0];
        end
    end

    // 3. 최종 결과 출력
    assign result_out = result_reg;

endmodule