// -----------------------------------------------------------------------------
// montgomery_multiplier.v  (Verilog-2001 compatible)
// Streaming / pipelined Montgomery multiplier
// Computes: (A * B * R_inv) mod q
// - WORD_WIDTH = W (e.g., 36), R = 2^W
// - q_inv = R - modInverse(q, R)  // i.e., q_inv == (-q^{-1}) mod R
// - Latency = 4 cycles after valid_in
// - Throughput = 1 op / cycle (after pipeline filled)
// - No backpressure (always consumes when valid_in=1)
// -----------------------------------------------------------------------------
module montgomery_multiplier #(
    parameter WORD_WIDTH = 36
)(
    input  clk,
    input  rst_n,

    input                  valid_in,
    input  [WORD_WIDTH-1:0] A,
    input  [WORD_WIDTH-1:0] B,
    input  [WORD_WIDTH-1:0] q,
    input  [WORD_WIDTH-1:0] q_inv,

    output                 valid_out,
    output [WORD_WIDTH-1:0] result
);
    // -----------------------
    // Valid pipeline (4 deep)
    // -----------------------
    reg [3:0] vld;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) vld <= 4'b0000;
        else         vld <= {vld[2:0], valid_in};
    end
    assign valid_out = vld[3];

    // -----------------------
    // Stage 1: T = A * B
    // Also pipeline q, q_inv for alignment
    // -----------------------
    reg [2*WORD_WIDTH-1:0] T_s1;
    reg [WORD_WIDTH-1:0]   q_s1;
    reg [WORD_WIDTH-1:0]   qinv_s1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            T_s1     <= {2*WORD_WIDTH{1'b0}};
            q_s1     <= {WORD_WIDTH{1'b0}};
            qinv_s1  <= {WORD_WIDTH{1'b0}};
        end else if (valid_in) begin
            T_s1     <= A * B;
            q_s1     <= q;
            qinv_s1  <= q_inv;
        end
    end

    // -----------------------
    // Stage 2: m = (T_low * q_inv) mod R
    // Keep T and q for next stage
    // -----------------------
    reg [2*WORD_WIDTH-1:0] T_s2;
    reg [WORD_WIDTH-1:0]   q_s2;
    reg [WORD_WIDTH-1:0]   m_s2;

    wire [WORD_WIDTH-1:0]  T_low_s1;
    assign T_low_s1 = T_s1[WORD_WIDTH-1:0];

    wire [WORD_WIDTH-1:0]  m_comb_s2;
    assign m_comb_s2 = T_low_s1 * qinv_s1; // truncated to W bits (mod R)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            T_s2 <= {2*WORD_WIDTH{1'b0}};
            q_s2 <= {WORD_WIDTH{1'b0}};
            m_s2 <= {WORD_WIDTH{1'b0}};
        end else if (vld[0]) begin
            T_s2 <= T_s1;
            q_s2 <= q_s1;
            m_s2 <= m_comb_s2;
        end
    end

    // -----------------------
    // Stage 3: U = (T + m*q) >> W
    // U needs W+1 bits (carry kept)
    // -----------------------
    reg [WORD_WIDTH:0]     U_s3;   // W+1 bits
    reg [WORD_WIDTH-1:0]   q_s3;

    wire [2*WORD_WIDTH-1:0] mq_s2;
    assign mq_s2 = m_s2 * q_s2;

    wire [2*WORD_WIDTH:0]   sum_s2;
    assign sum_s2 = {1'b0, T_s2} + {1'b0, mq_s2};

    wire [WORD_WIDTH:0]     U_comb_s3;
    assign U_comb_s3 = sum_s2[2*WORD_WIDTH:WORD_WIDTH]; // >> W

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            U_s3 <= {WORD_WIDTH+1{1'b0}};
            q_s3 <= {WORD_WIDTH{1'b0}};
        end else if (vld[1]) begin
            U_s3 <= U_comb_s3;
            q_s3 <= q_s2;
        end
    end

    // -----------------------
    // Stage 4: res = (U >= q) ? U - q : U
    // -----------------------
    reg [WORD_WIDTH-1:0] result_s4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_s4 <= {WORD_WIDTH{1'b0}};
        end else if (vld[2]) begin
            if (U_s3 >= q_s3)
                result_s4 <= U_s3 - q_s3;
            else
                result_s4 <= U_s3[WORD_WIDTH-1:0];
        end
    end

    assign result = result_s4;

endmodule

