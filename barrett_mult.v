// -----------------------------------------------------------------------------
// barrett_mult.v (Verilog-2001)
// v3.4 - Readability-Optimized Flexible Barrett multiplier
//
// [!!] This file is identical to your v3.4 except for a simulation guard that
// checks q_width is one of {42,58,59,60} when valid_in=1.
// -----------------------------------------------------------------------------
// `include "ntt_params.vh"
`timescale 1ns/1ps
`default_nettype none

module barrett_mult #(
    parameter integer WORD_WIDTH = 60 // e.g., 60 or 64
)(
    input  wire                       clk,
    input  wire                       rst_n,

    input  wire                       valid_in,
    input  wire [WORD_WIDTH-1:0]      A,
    input  wire [WORD_WIDTH-1:0]      B,
    input  wire [WORD_WIDTH-1:0]      q,
    input  wire [2*WORD_WIDTH-1:0]    mu,
    input  wire [5:0]                 q_width,

    output wire                       valid_out,
    output wire [WORD_WIDTH-1:0]      result
);

    // Pipeline for valid signal (4 stages)
    reg [3:0] vld;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) vld <= 4'b0;
        else        vld <= {vld[2:0], valid_in};
    end
    assign valid_out = vld[3];

    // =========================================================================
    // Stage 1: Capture inputs, compute T = A * B
    // =========================================================================
    reg [2*WORD_WIDTH-1:0] T_s1;
    reg [WORD_WIDTH-1:0]   q_s1;
    reg [2*WORD_WIDTH-1:0] mu_s1;
    reg [5:0]              q_width_s1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            T_s1       <= {2*WORD_WIDTH{1'b0}};
            q_s1       <= {WORD_WIDTH{1'b0}};
            mu_s1      <= {2*WORD_WIDTH{1'b0}};
            q_width_s1 <= 6'b0;
        end else if (valid_in) begin
            T_s1       <= A * B;
            q_s1       <= q;
            mu_s1      <= mu;
            q_width_s1 <= q_width;
        end
    end

    // =========================================================================
    // Stage 2: Compute P = (T >> (q_width - 1)) * mu
    // =========================================================================
    reg [3*WORD_WIDTH:0]   P_s2;
    reg [2*WORD_WIDTH-1:0] T_s2;
    reg [WORD_WIDTH-1:0]   q_s2;
    reg [5:0]              q_width_s2;

    // Pre-calculate shift results for supported q_width
    wire [2*WORD_WIDTH-1:0] T_shifted_for_42 = T_s1 >> (42 - 1);
    wire [2*WORD_WIDTH-1:0] T_shifted_for_58 = T_s1 >> (58 - 1);
    wire [2*WORD_WIDTH-1:0] T_shifted_for_59 = T_s1 >> (59 - 1);
    wire [2*WORD_WIDTH-1:0] T_shifted_for_60 = T_s1 >> (60 - 1);

    reg [2*WORD_WIDTH-1:0] T_shifted_s1;
    always @(*) begin
        case (q_width_s1)
            42: T_shifted_s1 = T_shifted_for_42;
            58: T_shifted_s1 = T_shifted_for_58;
            59: T_shifted_s1 = T_shifted_for_59;
            60: T_shifted_s1 = T_shifted_for_60;
            default: T_shifted_s1 = {2*WORD_WIDTH{1'b0}}; // sim-guard fallback
        endcase
    end
    //wire [WORD_WIDTH:0] Ahat_s1 = T_shifted_s1[WORD_WIDTH:0];
    wire [2*WORD_WIDTH-1:0] Ahat_s1 = T_shifted_s1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            P_s2       <= {(3*WORD_WIDTH+1){1'b0}};
            T_s2       <= {(2*WORD_WIDTH){1'b0}};
            q_s2       <= {WORD_WIDTH{1'b0}};
            q_width_s2 <= 6'b0;
        end else if (vld[0]) begin
            P_s2       <= Ahat_s1 * mu_s1;
            T_s2       <= T_s1;
            q_s2       <= q_s1;
            q_width_s2 <= q_width_s1;
        end
    end

    // =========================================================================
    // Stage 3: Compute q_est, sub_val = q_est * q
    // =========================================================================
    reg [3*WORD_WIDTH-1:0] sub_val_s3;
    reg [2*WORD_WIDTH-1:0] T_s3;
    reg [WORD_WIDTH-1:0]   q_s3;

    // Pre-calculate shift results for supported q_width
    wire [3*WORD_WIDTH:0] P_shifted_for_42 = P_s2 >> (42 + 1);
    wire [3*WORD_WIDTH:0] P_shifted_for_58 = P_s2 >> (58 + 1);
    wire [3*WORD_WIDTH:0] P_shifted_for_59 = P_s2 >> (59 + 1);
    wire [3*WORD_WIDTH:0] P_shifted_for_60 = P_s2 >> (60 + 1);

    reg [3*WORD_WIDTH:0] P_shifted_s2;
    always @(*) begin
        case (q_width_s2)
            42: P_shifted_s2 = P_shifted_for_42;
            58: P_shifted_s2 = P_shifted_for_58;
            59: P_shifted_s2 = P_shifted_for_59;
            60: P_shifted_s2 = P_shifted_for_60;
            default: P_shifted_s2 = {(3*WORD_WIDTH+1){1'b0}}; // sim-guard fallback
        endcase
    end
    wire [2*WORD_WIDTH-1:0] q_est_s2 = P_shifted_s2[2*WORD_WIDTH-1:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sub_val_s3 <= {(3*WORD_WIDTH){1'b0}};
            T_s3       <= {(2*WORD_WIDTH){1'b0}};
            q_s3       <= {WORD_WIDTH{1'b0}};
        end else if (vld[1]) begin
            sub_val_s3 <= q_est_s2 * q_s2;
            T_s3       <= T_s2;
            q_s3       <= q_s2;
        end
    end

    // =========================================================================
    // Stage 4: r = T - sub_val, apply up to 2 corrections
    // =========================================================================
    reg [WORD_WIDTH-1:0] res_s4;

    wire [3*WORD_WIDTH:0] T_extended_s3   = { {WORD_WIDTH+1{1'b0}}, T_s3 };
    wire [3*WORD_WIDTH:0] sub_extended_s3 = { 1'b0, sub_val_s3 };
    wire [3*WORD_WIDTH:0] r_full_s4       = T_extended_s3 - sub_extended_s3;

    wire [WORD_WIDTH:0] r0 = r_full_s4[WORD_WIDTH:0];
    wire [WORD_WIDTH:0] r1 = (r0 >= q_s3) ? (r0 - q_s3) : r0;
    wire [WORD_WIDTH:0] r2 = (r1 >= q_s3) ? (r1 - q_s3) : r1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            res_s4 <= {WORD_WIDTH{1'b0}};
        end else if (vld[2]) begin
            res_s4 <= r2[WORD_WIDTH-1:0];
        end
    end

    assign result = res_s4;

    // -------------------------------------------------------------------------
    // Simulation guard: only allow q_width ? {42,58,59,60} when valid_in=1
    // (synth tools ignore this block)
    // -------------------------------------------------------------------------
    // synthesis translate_off
    always @(posedge clk) if (valid_in) begin
        if (!(q_width==6'd42 || q_width==6'd58 || q_width==6'd59 || q_width==6'd60)) begin
            $display("[%0t][barrett_mult] ERROR: Unsupported q_width=%0d (allowed: 42,58,59,60).",
                     $time, q_width);
            $stop; // or $finish;
        end
    end
    // synthesis translate_on

endmodule

`default_nettype wire




// -----------------------------------------------------------------------------
// barrett_mult.v  (Verilog-2001)
// v2.2 - Final Barrett (k=2) modular multiplier with detailed documentation
//
// Purpose:
//   - Drop-in replacement for montgomery_mult in streaming NTT pipelines.
//   - Keeps the SAME port list and SAME 4-cycle latency, so upper-level RTL
//     can swap montgomery_mult -> barrett_mult with minimal edits.
//   - Module name is changed to barrett_mult for clarity.
//
// Functionality:
//   - Computes (A * B) mod q using Barrett reduction (k=2).
//   - Latency: 4 cycles from valid_in to valid_out.
//   - Throughput: 1 op/cycle once pipeline is full.
//
// Pre-computation Requirement:
//   - Input 'mu' must be precomputed as:
//         mu = floor(2^(2*WORD_WIDTH) / q)
//   - Width of mu is 2*WORD_WIDTH bits.
//   - This is analogous to 'q_inv' in Montgomery, but note the difference:
//     Montgomery expects (-q^{-1} mod R), while Barrett expects μ.
//
// Domain Note:
//   - Output is in the STANDARD modular domain [0, q-1].
//   - It is NOT in Montgomery domain. Ensure twiddles/data/constants are also
//     in the standard domain if you replace Montgomery with Barrett.
//   - If the rest of your design assumes Montgomery domain, you cannot simply
//     swap this module without also regenerating twiddle tables in standard
//     domain.
//
// Algorithm (k=2 Barrett):
//   Inputs: A, B (operands < q), q (modulus), mu = floor(2^(2W)/q)
//   Step 1) T = A * B                                (2W bits)
//   Step 2) Ahat = T >> (W-1)                        (W+1 bits)
//           P = Ahat * mu                            (3W+1 bits)
//   Step 3) q_est = P >> (W+1)                       (≈ 2W bits)
//           sub_val = q_est * q                      (≈ 3W bits)
//   Step 4) r_full = T - sub_val                     (up to 3W+1 bits)
//           r0 = r_full[W:0]                         (W+1 bits)
//           r1 = (r0 >= q) ? (r0 - q) : r0
//           r2 = (r1 >= q) ? (r1 - q) : r1
//           result = r2[W-1:0]                       (final [0, q-1])
//
// Pipeline stages (4):
//   S1: Multiply A*B, register q, mu
//   S2: Compute P = (T >> (W-1)) * mu
//   S3: Compute q_est, sub_val = q_est * q
//   S4: Subtract, apply up to 2 corrections, produce result
//
// Tooling constraints:
//   - Verilog-2001 only (no SystemVerilog).
//   - ModelSim 2020.1 friendly: no declarations inside always blocks.
// -----------------------------------------------------------------------------
