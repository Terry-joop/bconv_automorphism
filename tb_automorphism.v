// -----------------------------------------------------------------------------
// Testbench for mod_mult_16x16
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_automorphism;

    // --- Parameters ---
    parameter NUM_VECTORS = 100; // txt 파일에 저장된 벡터의 개수
    parameter WIDTH       = 16;
    parameter CLK_PERIOD  = 4;   // ns, 클럭 주기

    // --- Internal Signals ---
    reg                    clk;
    reg                    rst_n;
    reg  [WIDTH-1:0]       i_in;
    reg  [WIDTH-1:0]       k_in;
    wire [WIDTH-1:0]       result_out;
    reg  [WIDTH-1:0]       expected_result;

    // --- Memories to store test vectors from files ---
    reg [WIDTH-1:0] i_memory      [0:NUM_VECTORS-1];
    reg [WIDTH-1:0] k_memory      [0:NUM_VECTORS-1];
    reg [WIDTH-1:0] result_memory [0:NUM_VECTORS-1];

    integer i; // Loop counter
    integer error_count;

    // --- DUT (Device Under Test) Instantiation ---
    automorphism dut (
        .clk        (clk),
        .rst_n    (rst_n),
        .i_in       (i_in),
        .k_in       (k_in),
        .result_out (result_out)
    );

    // --- Clock Generation ---
    initial begin
        clk = 0;
    end
    always # (CLK_PERIOD / 2) clk = ~clk;

    // --- Main Test Sequence ---
    initial begin
        // 1. Initialization
        rst_n     = 1;
        i_in        = 0;
        k_in        = 0;
        error_count = 0;
        $display("--- Simulation Start ---");

        // 2. Load vectors from files into memories
        $readmemh("../au_test_vectors/i_vectors.txt", i_memory);
        $readmemh("../au_test_vectors/k_vectors.txt", k_memory);
        $readmemh("../au_test_vectors/result_vectors.txt", result_memory);
        $display("Test vectors loaded from files.");

        // 3. Apply Reset
        rst_n = 0;
        #(CLK_PERIOD * 2);
        rst_n = 1;
        $display("Reset applied.");

        // 4. Apply vectors and check results
        for (i = 0; i < NUM_VECTORS; i = i + 1) begin
            @(posedge clk);
            
            // Apply inputs
            i_in <= i_memory[i];
            k_in <= k_memory[i];
            
            // Load expected result for the NEXT cycle's check
            expected_result <= result_memory[i-1];

            // DUT is registered, so the output appears on the next clock cycle.
            // We only check if i > 0 to avoid checking the reset state.
            if (i > 1) begin
                // Use !== for safer comparison (checks for X and Z)
                if (result_out !== expected_result) begin
                    error_count = error_count + 1;
                    $display("ERROR at vector %0d: i=%h, k=%h -> result=%h (expected=%h)",
                             i-1, i_memory[i-1], k_memory[i-1], result_out, expected_result);
                end
            end
        end

        // Wait for the last operation to complete
        @(posedge clk);
        if (result_out !== expected_result) begin
             error_count = error_count + 1;
             $display("ERROR at vector %0d: i=%h, k=%h -> result=%h (expected=%h)",
                             i-1, i_memory[i-1], k_memory[i-1], result_out, expected_result);
        end

		expected_result <= result_memory[NUM_VECTORS-1];

		@(posedge clk);
        if (result_out !== expected_result) begin
             error_count = error_count + 1;
             $display("ERROR at vector %0d: i=%h, k=%h -> result=%h (expected=%h)",
                             i-1, i_memory[i-1], k_memory[i-1], result_out, expected_result);
        end
        
        #(CLK_PERIOD * 2);

        // 5. Final Report
        if (error_count == 0) begin
            $display("--- TEST PASSED ---");
            $display("All %0d vectors matched.", NUM_VECTORS);
        end else begin
            $display("--- TEST FAILED ---");
            $display("%0d errors found out of %0d vectors.", error_count, NUM_VECTORS);
        end

        $stop; // End simulation
    end

endmodule