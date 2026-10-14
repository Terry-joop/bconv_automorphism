module shoup_mult #(
    parameter WORD_WIDTH = 36,
    parameter K_WIDTH    = 36
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     valid_in,
    input  wire [WORD_WIDTH-1:0]    a,       // operand in [0, q)
    input  wire [WORD_WIDTH-1:0]    ratio,   // constant multiplier (e.g., z or z^2)
    input  wire [WORD_WIDTH-1:0]    z_pre,   // floor(ratio * 2^K / q)
    input  wire [WORD_WIDTH-1:0]    q,
    output wire                     valid_out,
    output reg  [WORD_WIDTH-1:0]    result   // registered stage-2 output
);
    // -------------------------------------------------------------------------
    // Design-time guard
    // -------------------------------------------------------------------------
    initial begin
        if (K_WIDTH != WORD_WIDTH) begin
            $fatal(1, "Shoup: K_WIDTH(%0d) must equal WORD_WIDTH(%0d) for robust path.",
                      K_WIDTH, WORD_WIDTH);
        end
    end
// `ifdef SIM
//     // Optional runtime guards (simulation only)
//     always @(posedge clk) if (valid_in) begin
//         if (a     >= q) $fatal(1, "Shoup: a >= q (a=%h q=%h)", a, q);
//         if (ratio >= q) $fatal(1, "Shoup: ratio >= q (ratio=%h q=%h)", ratio, q);
//     end
// `endif
    // -------------------------------------------------------------------------
    // Valid pipeline (2 deep)
    // -------------------------------------------------------------------------
    reg [1:0] vld;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) vld <= 2'b00;
        else       vld <= {vld[0], valid_in};
    end
    assign valid_out = vld[1];
    // -------------------------------------------------------------------------
    // Stage 1:
    //   q_est = floor( (a * z_pre) >> K )
    //   keep full product a*ratio for stage 2
    // -------------------------------------------------------------------------
    reg  [2*WORD_WIDTH-1:0] AR_s1;    // full product a*ratio
    reg  [WORD_WIDTH-1:0]   q_s1;
    reg  [WORD_WIDTH-1:0]   q_est_s1; // quotient estimate
    wire [2*WORD_WIDTH-1:0] a_mul_zpre = a * z_pre;
    wire [WORD_WIDTH-1:0]   q_est_comb = a_mul_zpre >> K_WIDTH;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            AR_s1    <= {2*WORD_WIDTH{1'b0}};
            q_s1     <= {WORD_WIDTH{1'b0}};
            q_est_s1 <= {WORD_WIDTH{1'b0}};
        end else if (valid_in) begin
            AR_s1    <= a * ratio;
            q_s1     <= q;
            q_est_s1 <= q_est_comb;
        end
    end
    // -------------------------------------------------------------------------
    // Stage 2 (robust reduction)
    //   T  = AR_s1 - q_est*q
    //   if (T < 0)   T += q
    //   if (T >= q)  T -= q
    //   if (T >= q)  T -= q
    //
    // Use signed (2*W+1) to detect negativity safely.
    // -------------------------------------------------------------------------
    wire [2*WORD_WIDTH-1:0] qmul   = q_est_s1 * q_s1;
    wire signed [2*WORD_WIDTH:0] T = {1'b0, AR_s1} - {1'b0, qmul};
    // Step 0: if negative, add q once
    wire signed [2*WORD_WIDTH:0] U0 =
        T[2*WORD_WIDTH] ? (T + {{(2*WORD_WIDTH+1-WORD_WIDTH){1'b0}}, q_s1}) : T;
    // Step 1: subtract q once if still >= q
    wire signed [2*WORD_WIDTH:0] U1_try = U0 - {{(2*WORD_WIDTH+1-WORD_WIDTH){1'b0}}, q_s1};
    wire                         U1_ge0 = ~U1_try[2*WORD_WIDTH];
    wire signed [2*WORD_WIDTH:0] U1     = U1_ge0 ? U1_try : U0;
    // Step 2: subtract q again if still >= q (rare but safe)
    wire signed [2*WORD_WIDTH:0] U2_try = U1 - {{(2*WORD_WIDTH+1-WORD_WIDTH){1'b0}}, q_s1};
    wire                         U2_ge0 = ~U2_try[2*WORD_WIDTH];
    wire signed [2*WORD_WIDTH:0] U2     = U2_ge0 ? U2_try : U1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            result <= {WORD_WIDTH{1'b0}};
        end else if (vld[0]) begin
            result <= U2[WORD_WIDTH-1:0];
        end
    end
endmodule