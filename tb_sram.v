//
// Testbench for sram_1024w_32b
//
`timescale 1ns / 1ps

module tb_sram_1024w_32b;

  //================================================================
  // Parameters
  //================================================================
  parameter BITS        = 32;
  parameter WORDS       = 1024;
  parameter ADDR_WIDTH  = 10; // 2^10 = 1024
  parameter CLK_PERIOD  = 10;   // 10 ns clock period (100 MHz)

  //================================================================
  // Signal Declarations
  //================================================================
  reg                   CLK;
  reg                   CEN;
  reg   [3:0]           WEN;
  reg   [ADDR_WIDTH-1:0] A;
  reg   [BITS-1:0]      D;
  reg   [2:0]           EMA;
  reg                   GWEN;
  reg                   RETN;

  wire  [BITS-1:0]      Q;

  // Testbench internal variables
  integer               error_count;
  integer               i;
  reg   [BITS-1:0]      read_data;
  reg   [BITS-1:0]      expected_data;
  reg   [BITS-1:0]      sram_mirror [0:WORDS-1]; // For full memory test

  //================================================================
  // Instantiate the Design Under Test (DUT)
  //================================================================
  sram_1024w_32b uut (
    .Q(Q),
    .CLK(CLK),
    .CEN(CEN),
    .WEN(WEN),
    .A(A),
    .D(D),
    .EMA(EMA),
    .GWEN(GWEN),
    .RETN(RETN)
  );

  //================================================================
  // Clock Generator
  //================================================================
  initial begin
    CLK = 0;
    forever #(CLK_PERIOD / 2) CLK = ~CLK;
  end

  //================================================================
  // TASKS for SRAM operations
  //================================================================

  // Task to initialize all input signals to an idle state
  task initialize_ports;
  begin
    CEN   = 1'b1;       // Disabled
    GWEN  = 1'b1;       // Write controlled by WEN
    WEN   = 4'b1111;    // Write disabled (active low)
    RETN  = 1'b1;       // Active mode
    EMA   = 3'b000;
    A     = {ADDR_WIDTH{1'b0}};
    D     = {BITS{1'b0}};
    error_count = 0;
    $display("INFO: Ports Initialized at time %0t.", $time);
  end
  endtask

  // Task to perform a full 32-bit write operation
  task sram_write;
    input [ADDR_WIDTH-1:0] addr;
    input [BITS-1:0]       data;
  begin
    @(posedge CLK);
    CEN   = 1'b0;
    GWEN  = 1'b0;       // Use global write for simplicity
    WEN   = 4'b1111;    // Ignored when GWEN is active
    A     = addr;
    D     = data;
    @(posedge CLK);
    CEN   = 1'b1;
    GWEN  = 1'b1;
    A     = {ADDR_WIDTH{1'bx}}; // Set to X to catch potential issues
    D     = {BITS{1'bx}};
  end
  endtask

  // Task to perform a byte-masked write operation
  task sram_masked_write;
    input [ADDR_WIDTH-1:0] addr;
    input [BITS-1:0]       data;
    input [3:0]            mask; // WEN mask
  begin
    @(posedge CLK);
    CEN   = 1'b0;
    GWEN  = 1'b1;       // Must be high to use WEN
    WEN   = mask;       // Active low mask
    A     = addr;
    D     = data;
    @(posedge CLK);
    CEN   = 1'b1;
    WEN   = 4'b1111;
    A     = {ADDR_WIDTH{1'bx}};
    D     = {BITS{1'bx}};
  end
  endtask
  
  // Task to perform a read operation (handles 1-cycle read latency)
  task sram_read;
    input [ADDR_WIDTH-1:0] addr;
    output [BITS-1:0]      data_out;
  begin
    @(posedge CLK);
    // Setup read command on the bus
    CEN   = 1'b0;
    GWEN  = 1'b1;
    WEN   = 4'b1111;    // This combination enables a read
    A     = addr;

    @(posedge CLK);
    // Data is valid on Q after this rising edge
    data_out = Q;
    
    // Go back to idle state
    CEN   = 1'b1;
    A     = {ADDR_WIDTH{1'bx}};
  end
  endtask

  //================================================================
  // Main Test Sequence
  //================================================================
  initial begin
    initialize_ports();
    #CLK_PERIOD;

    // --- 1. Basic Write/Read Test ---
    $display("\n--- [TEST 1] Starting Basic Write/Read Test ---");
    sram_write(10'h05A, 32'hDEADBEEF);
    sram_read(10'h05A, read_data);
    expected_data = 32'hDEADBEEF;
    if (read_data === expected_data) begin
      $display("SUCCESS: Read data %h matches expected data %h.", read_data, expected_data);
    end else begin
      $display("ERROR: Read data %h does NOT match expected data %h.", read_data, expected_data);
      error_count = error_count + 1;
    end
    $display("--- [TEST 1] Finished ---");

    // --- 2. Full Memory Write/Read Test ---
    $display("\n--- [TEST 2] Starting Full Memory Test ---");
    $display("Writing to all %0d addresses...", WORDS);
    for (i = 0; i < WORDS; i = i + 1) begin
      sram_mirror[i] = i + 32'h1000; // Store expected value
      sram_write(i, sram_mirror[i]);
    end
    
    $display("Reading from all %0d addresses and verifying...", WORDS);
    for (i = 0; i < WORDS; i = i + 1) begin
      sram_read(i, read_data);
      if (read_data !== sram_mirror[i]) begin
        $display("ERROR @ Address %h: Read data %h, Expected %h", i, read_data, sram_mirror[i]);
        error_count = error_count + 1;
      end
    end
    $display("--- [TEST 2] Finished ---");
    
    // --- 3. Write Mask (WEN) Test ---
    $display("\n--- [TEST 3] Starting Write Mask (WEN) Test ---");
    // First, write an initial pattern
    sram_write(10'h1FF, 32'hAAAAAAAA);
    // Now, perform a masked write to modify only the 2nd and 4th bytes
    // WEN is active low, so 4'b0101 enables writes for bytes 3 and 1.
    sram_masked_write(10'h1FF, 32'h12345678, 4'b0101);
    sram_read(10'h1FF, read_data);
    expected_data = 32'h12AA56AA; // Byte3=12, Byte2=AA, Byte1=56, Byte0=AA
    if (read_data === expected_data) begin
      $display("SUCCESS: Masked write successful. Read: %h, Expected: %h", read_data, expected_data);
    end else begin
      $display("ERROR: Masked write failed. Read: %h, Expected: %h", read_data, expected_data);
      error_count = error_count + 1;
    end
    $display("--- [TEST 3] Finished ---");
    
    // --- 4. Global Write Enable (GWEN) Test ---
    $display("\n--- [TEST 4] Starting Global Write (GWEN) Test ---");
    // GWEN should write all bytes, regardless of WEN
    @(posedge CLK);
    CEN   = 1'b0;
    GWEN  = 1'b0;
    WEN   = 4'b1111; // Set WEN to 'no write'
    A     = 10'h2AA;
    D     = 32'hC0DEC0DE;
    @(posedge CLK);
    CEN   = 1'b1;
    GWEN  = 1'b1;
    sram_read(10'h2AA, read_data);
    expected_data = 32'hC0DEC0DE;
    if (read_data === expected_data) begin
        $display("SUCCESS: GWEN correctly overrode WEN. Data: %h", read_data);
    end else begin
        $display("ERROR: GWEN failed to override WEN. Read: %h, Expected: %h", read_data, expected_data);
        error_count = error_count + 1;
    end
    $display("--- [TEST 4] Finished ---");

    // --- 5. Chip Enable (CEN) Test ---
    $display("\n--- [TEST 5] Starting Chip Enable (CEN) Test ---");
    // Write an initial value
    sram_write(10'h300, 32'hFEEDFACE);
    // Attempt to write with CEN disabled
    @(posedge CLK);
    CEN   = 1'b1; // <--- CHIP DISABLED
    GWEN  = 1'b0;
    A     = 10'h300;
    D     = 32'h00000000;
    @(posedge CLK);
    GWEN  = 1'b1;
    // Read back and check if the original value is still there
    sram_read(10'h300, read_data);
    expected_data = 32'hFEEDFACE;
    if (read_data === expected_data) begin
        $display("SUCCESS: Write was correctly blocked by CEN=1. Data: %h", read_data);
    end else begin
        $display("ERROR: Write occurred even with CEN=1. Read: %h, Expected: %h", read_data, expected_data);
        error_count = error_count + 1;
    end
    $display("--- [TEST 5] Finished ---");
    
    // --- 6. Retention (RETN) Test ---
    $display("\n--- [TEST 6] Starting Retention (RETN) Test ---");
    // Write data to a location
    sram_write(10'h123, 32'hABCDEFFF);
    $display("Data written. Entering retention mode...");
    // Enter retention mode
    @(posedge CLK);
    RETN = 1'b0;
    #5; // Wait a short time
    if (Q === 32'h00000000) begin
      $display("SUCCESS: Output Q correctly driven to 0 in retention mode.");
    end else begin
      $display("ERROR: Output Q is %h, expected 0 in retention mode.", Q);
      error_count = error_count + 1;
    end
    
    // Wait for a few clock cycles in retention mode
    repeat(3) @(posedge CLK);
    
    // Exit retention mode
    $display("Exiting retention mode...");
    @(posedge CLK);
    RETN = 1'b1;
    
    // Read the data back to see if it was retained
    sram_read(10'h123, read_data);
    expected_data = 32'hABCDEFFF;
    if (read_data === expected_data) begin
        $display("SUCCESS: Data was correctly retained. Read: %h", read_data);
    end else begin
        $display("ERROR: Data was corrupted during retention. Read: %h, Expected: %h", read_data, expected_data);
        error_count = error_count + 1;
    end
    $display("--- [TEST 6] Finished ---");


    //================================================================
    // Final Summary
    //================================================================
    $display("\n\n================================================");
    if (error_count == 0) begin
      $display("****** ALL TESTS PASSED! ******");
    end else begin
      $display("****** TEST FAILED with %0d errors. ******", error_count);
    end
    $display("================================================\n");

    $finish;
  end

endmodule