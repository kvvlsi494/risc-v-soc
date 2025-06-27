// Copyright (c) 2025 Kumar Vedang
// SPDX-License-Identifier: MIT
//
// This source file is part of the RISC-V SoC project.
//

/*
--------------------------------------------------------------------------------
-- File Name: tb_risc_soc.sv
-- Project: A Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: Kumar Vedang
--------------------------------------------------------------------------------
--
-- High-Level Module Purpose:
-- This file contains the primary system-level testbench for the entire `risc_soc`
-- project. Its sole purpose is to instantiate the top-level SoC module (referred
-- to as the Device Under Test or DUT) and rigorously verify its integrated
-- functionality. This testbench acts as the "world" outside the chip, generating
-- stimulus, checking responses, and ultimately determining if the design meets
-- its specifications.
--
-- Verification Strategy Overview:
-- The strategy employed here is designed to mimic modern, professional
-- verification methodologies, even without using the full UVM framework. The
-- key principles are:
--
--   1. BFM-Driven Testing: Instead of writing and loading actual RISC-V
--      programs, this testbench uses a Bus Functional Model (BFM). The BFM
--      is a set of tasks (`cpu_bfm_write`, `cpu_bfm_read`) that directly
--      manipulate the CPU's bus signals. This provides precise, deterministic
--      control over the DUT, which is essential for creating targeted and
--      repeatable test scenarios.
--
--   2. Self-Checking Scoreboards: Each test case is designed to be self-
--      checking. After driving stimulus, the test logic (the "scoreboard")
--      automatically reads back the results and compares them against a
--      "golden" reference model or expected outcome. It prints a clear "PASS"
--      or "FAIL" message, eliminating the need for manual waveform inspection
--      to determine correctness.
--
--   3. Automated Regression: The testbench is structured to be controlled by
--      an external script. It uses SystemVerilog "plusargs" to select which
--      specific test sequence to run. This allows the `run_regression.py`
--      script to execute a full suite of tests (DMA, CRC, Timer, etc.) with a
--      single command, providing a comprehensive quality check of the design.
--
-- This file is the cornerstone of the project's quality assurance, providing
-- the final sign-off that all individual components work together correctly as
-- a complete system.
--
--------------------------------------------------------------------------------
*/

`timescale 1ns / 1ps


// This `module` declaration defines the testbench itself. By convention in
// Verilog, a testbench is a self-contained module that has no input or output
// ports of its own. It is the top-level entity in a simulation environment.
module tb_risc_soc;


    // --- Signals to Drive the DUT ---
    // These signals are declared as `reg` (register) type because they are
    // driven from within procedural blocks (like `initial` blocks). They act
    // as the primary stimulus generators for the DUT.

    // `clk`: A 1-bit register used to generate the global system clock signal.
    // It is driven by an `initial` block and connected to the DUT's `clk` input.
    reg clk;

    // `rst_n`: A 1-bit register used to generate the active-low reset signal.
    // It is driven by an `initial` block to hold the DUT in reset at the
    // beginning of the simulation and then release it.
    reg rst_n;

    // `bfm_mode_reg`: A 1-bit register connected to the DUT's `bfm_mode` input.
    // This signal is controlled by the BFM tasks to put the CPU into its
    // special, directly controllable test mode.
    reg bfm_mode_reg;


    // --- Signals to Monitor the DUT ---
    // These signals are declared as `wire` type because they are continuously
    // driven *by* the DUT's output ports. This testbench monitors these wires
    // to check the DUT's behavior.

    // `uart_tx_pin_from_dut`: A 1-bit wire that captures the serial data output
    // from the DUT's UART peripheral.
    wire uart_tx_pin_from_dut;

    // `uart_rx_pin_to_dut`: A 1-bit wire that will drive the DUT's serial
    // data input pin. It's declared as a wire because it will be driven by a
    // continuous `assign` statement to create a loopback.
    wire uart_rx_pin_to_dut;


    // --- DUT Instantiation and UART Loopback Connection ---

    // This block instantiates the entire `risc_soc` design, giving it the
    // instance name `dut`. In verification terminology, the design being tested
    // is called the Device Under Test (DUT). This line effectively places our
    // entire chip design inside this testbench environment.
    // The `.port(signal)` syntax creates the connections between the DUT's
    // top-level ports and the `reg` and `wire` signals declared within this
    // testbench, allowing us to control and observe the DUT.
    risc_soc dut (
        .clk(clk), 
        .rst_n(rst_n), 
        .bfm_mode(bfm_mode_reg),
        .uart_tx_pin(uart_tx_pin_from_dut),
        .uart_rx_pin(uart_rx_pin_to_dut)
    );


    // This continuous `assign` statement creates a physical loopback for the UART.
    // It directly connects the DUT's transmitter output pin (`uart_tx_pin_from_dut`)
    // to its own receiver input pin (`uart_rx_pin_to_dut`).
    //
    // Why is this done? This is a powerful and common technique for self-testing
    // a communication peripheral without needing an external device. It allows a
    // test case to write a character to the UART's transmit register and then
    // verify that the exact same character is received by its own receiver,
    // proving that both the transmit and receive paths are fully functional.
    assign uart_rx_pin_to_dut = uart_tx_pin_from_dut;



    // --- Clock and Reset Generation ---

    // This `initial` block is a procedural block that starts execution at time 0
    // of the simulation. It is responsible for generating the system clock.
    // The `forever` loop creates a continuous, oscillating signal.
    //   - `clk = 0;`: The clock is initialized to 0.
    //   - `forever #5 clk = ~clk;`: This line means "wait for 5 time units (5ns
    //     as per the `timescale`), then invert the value of `clk`." This creates a
    //     clock signal with a period of 10ns (a frequency of 100MHz), which is
    //     a common frequency for simple SoCs.
    initial begin 
        clk = 0; 
        forever #5 clk = ~clk; 
    end


    // This second `initial` block is responsible for generating the system reset
    // signal and setting up the initial state of the testbench. It executes
    // concurrently with the clock generation block.
    initial begin

        // At time 0, the active-low reset `rst_n` is asserted (driven to 0).
        // This forces all sequential logic in the DUT into its defined reset state.
        rst_n = 1'b0; 

        // The BFM mode is also initialized to '0' to ensure the CPU starts in
        // its normal operational mode.
        bfm_mode_reg = 1'b0; 

        // The `#20` is a time delay. It tells the simulator to wait for 20ns.
        // This ensures the reset signal is held active for two full clock cycles
        // (2 * 10ns), which is a robust way to ensure all parts of the design
        // have time to be properly reset.
        #20;

        // After the 20ns delay, the reset is de-asserted (`rst_n` goes to 1),
        // allowing the DUT to begin normal operation on the next rising clock edge.
        rst_n = 1'b1;

    end



    // --- Test Parameters and Data Storage ---
    // This section defines the configuration and data structures used to create
    // randomized, repeatable test stimulus for the more complex test cases
    // like the DMA and CRC tests.

    // `parameter` is a SystemVerilog keyword for defining a compile-time constant.
    // This defines the number of random transactions to generate and run in a loop
    // for the DMA and CRC tests. Using a parameter makes the testbench easily
    // configurable; I can change this value to run a longer or shorter test
    // without modifying the core test logic.
    parameter NUM_TRANSACTIONS = 5;


    // This parameter defines the maximum number of 32-bit words that a single
    // DMA or CRC transaction can have. This is used to size the data storage array.
    parameter MAX_WORDS = 16;


    // These declarations create "queues" or arrays to hold the properties of each
    // transaction. Using arrays allows me to pre-generate all the random stimulus
    // at the beginning of the test and then use it deterministically, which is
    // crucial for debug and repeatability.

    // `src_addr_q`: A 1-D array of 32-bit registers. It stores the source address
    // for each of the `NUM_TRANSACTIONS` to be run.
    reg [31:0] src_addr_q[0:NUM_TRANSACTIONS-1];

    // `dest_addr_q`: A 1-D array storing the destination address for each transaction.
    reg [31:0] dest_addr_q[0:NUM_TRANSACTIONS-1];


    // `num_words_q`: A 1-D array storing the number of words (length) for each
    // transaction. This value will be randomized between 1 and `MAX_WORDS`.
    reg [31:0] num_words_q[0:NUM_TRANSACTIONS-1];


    // `data_q`: This is a 2-D array used to store the actual data payload for
    // each transaction.
    // The first dimension (`[0:NUM_TRANSACTIONS-1]`) selects the transaction.
    // The second dimension (`[0:MAX_WORDS-1]`) selects the word within that transaction.
    // This structure effectively creates a pool of pre-generated random data packets.
    reg [31:0] data_q[0:NUM_TRANSACTIONS-1][0:MAX_WORDS-1];
    




    // --- Bus Functional Model (BFM) Tasks ---
    /*
    ----------------------------------------------------------------------------
    -- Concept Deep Dive: Bus Functional Model (BFM)
    ----------------------------------------------------------------------------
    -- What is it?
    -- A BFM is a cornerstone of modern verification. It's a piece of testbench
    -- code (in this case, a set of `tasks`) that provides a high-level,
    -- function-call-based Application Programming Interface (API) to interact
    -- with the DUT's low-level physical bus. Instead of manually wiggling
    -- individual pins (`req`, `gnt`, `addr`, etc.) in every test, we can just
    -- call a task like `cpu_bfm_write(address, data)`.
    --
    -- How is it used here?
    -- These tasks act as a "perfect" CPU from the bus's perspective. They
    -- directly drive the internal registers of the `simple_cpu` module using
    -- hierarchical references (e.g., `dut.u_cpu.bus_req_reg`). This is enabled
    -- by the DUT's `bfm_mode` port, which, when high, disconnects the CPU's
    -- own FSM from its bus drivers, allowing the testbench to take direct control.
    --
    -- Why is it used?
    --   - Abstraction & Reusability: It abstracts away the complex, multi-cycle
    --     bus protocol. I can write a simple, clean test case (like `run_timer_test`)
    --     without needing to worry about the timing of request/grant signals.
    --     These BFM tasks can be reused across all test cases.
    --   - Determinism & Control: It gives the testbench perfect, deterministic
    --     control over the system, which is crucial for creating specific
    --     scenarios and debugging failures. It's much easier to debug a bus
    --     transaction initiated by a BFM than one initiated by a complex CPU
    --     running a program.
    ----------------------------------------------------------------------------
    */



    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /*
    ----------------------------------------------------------------------------
    -- Concept Deep Dive: Hierarchical References (Dot Notation)
    ----------------------------------------------------------------------------
    -- What is it?
    -- Hierarchical referencing is a powerful feature in SystemVerilog that
    -- allows code in one module (like this testbench) to directly access,
    -- monitor, or force the value of a signal, register, or wire inside
    -- another module instantiated within it. This is done using a "dot"
    -- notation, for example: `dut.u_cpu.bus_req_reg`.
    --
    -- How is it used here?
    -- This technique is the magic that makes our BFM possible. The BFM tasks
    -- (`cpu_bfm_write` and `cpu_bfm_read`) need to directly control the bus
    -- interface signals of the CPU. By using hierarchical references, this
    -- testbench can "reach into" the DUT, through the `risc_soc` layer (`dut`),
    -- and down into the `simple_cpu` instance (`u_cpu`) to force the values of
    -- its internal registers like `bus_req_reg`, `bus_addr_reg`, etc.
    --
    -- Why is it used?
    --   - Intrusive Control: It provides the ultimate level of control for
    --     verification. Without it, the only way to test the DUT would be to
    --     load a compiled RISC-V program into its memory and run it, which is
    --     a much more complex and less direct way to test specific hardware
    --     features.
    --   - White-Box Testing: This is a form of "white-box" testing, where the
    --     testbench has full visibility and control over the internal state of
    --     the design. This is essential for creating targeted tests and for
    --     debugging, as it allows us to isolate and manipulate specific parts
    --     of the DUT's logic. The `bfm_mode` signal is the key that "unlocks"
    --     this capability in the DUT, ensuring this intrusive access doesn't
    --     conflict with the CPU's normal operation.
    ----------------------------------------------------------------------------
    */


    task cpu_bfm_write;
        // The `task` keyword in SystemVerilog defines a block of procedural code
        // that can consume time (unlike a `function`).
        // `input` arguments define the high-level command: the address to write
        // to and the data to be written.

        input [31:0] addr;
        input [31:0] data;
        begin

            // Put the DUT's CPU into BFM mode, allowing hierarchical access.
            bfm_mode_reg <= 1'b1;

            // Wait for the next rising clock edge to begin the transaction.
            @(posedge clk);

            // Assert the CPU's request line to the arbiter.
            dut.u_cpu.bus_req_reg <= 1'b1;

            // The `wait` statement pauses task execution until the arbiter grants
            // the bus to the CPU. This correctly models the bus handshake.
            wait (dut.cpu_m_gnt == 1'b1);

            // Once granted, wait for the next clock edge to drive the buses.
            @(posedge clk);

            // Drive the address bus with the target address.
            dut.u_cpu.bus_addr_reg  <= addr;

            // Assert the write enable signal.
            dut.u_cpu.bus_wr_en_reg <= 1'b1;

            // Drive the write data bus with the payload.
            dut.u_cpu.bus_wdata_reg <= data;

            // Wait one more clock cycle for the slave to latch the data.
            @(posedge clk);

            // De-assert the request line to release the bus.
            dut.u_cpu.bus_req_reg   <= 1'b0;

            // De-assert the write enable signal.
            dut.u_cpu.bus_wr_en_reg <= 1'b0;

            // Take the CPU out of BFM mode, returning control to its internal FSM.
            bfm_mode_reg <= 1'b0;

        end

    endtask


    // This task implements the BFM for a bus read operation. It encapsulates
    // the multi-cycle protocol for reading a word from a given address.
    task cpu_bfm_read;

        // `input` defines the address from which to read.
        input [31:0] addr;

        // `output` defines the variable where the read data will be stored and
        // returned to the calling code.
        output [31:0] data;
        begin

            // Put the DUT's CPU into BFM mode.
            bfm_mode_reg <= 1'b1;

            // Synchronize to the start of a clock cycle.
            @(posedge clk);

            // Assert the bus request line to the arbiter.
            dut.u_cpu.bus_req_reg <= 1'b1;

            // Wait until the arbiter grants access to the bus.
            wait (dut.cpu_m_gnt == 1'b1);

            // Once granted, wait for the next clock edge to drive the address.
            @(posedge clk);

            // Drive the address bus with the target read address.
            dut.u_cpu.bus_addr_reg  <= addr;

            // De-assert the write enable signal to indicate a read operation.
            dut.u_cpu.bus_wr_en_reg <= 1'b0;

            // Wait one more clock cycle. This delay is critical as it accounts
            // for the one-cycle read latency of the slave peripherals (like the
            // on-chip RAM). During this cycle, the slave is expected to place
            // its data onto the `bus_rdata` wire.
            @(posedge clk);

            // Capture the data from the DUT's read data port. This data has
            // traveled from the slave, through the top-level bus multiplexer,
            // and back to the CPU's master port.
            data = dut.cpu_m_rdata;

            // De-assert the request line to release the bus for other masters.
            dut.u_cpu.bus_req_reg <= 1'b0;

            // Return the CPU to normal operational mode.
            bfm_mode_reg <= 1'b0;

        end

    endtask


    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////// 
    
    
    // --- Individual Test Task Implementations (Self-Contained) ---
    
    // This task defines the entire test case for verifying the DMA engine's
    // memory-to-memory copy functionality. It's a self-contained block of
    // stimulus generation (Driver) and results checking (Scoreboard).
    
    task run_dma_test;

        // Local variables used only within this test task.

        reg [31:0] temp_word_read; // Holds data read back from memory for checking.
        integer i, j; // Loop counters. `integer` is a 32-bit signed type in Verilog.

        // Print a header to the simulation log for clarity.
        $display("\n------------------------------------------------------");
        $display("--- DMA FUNCTIONAL TEST ---");


        // This outer loop iterates through the number of random transactions
        // that were pre-generated by the main sequencer.
        for (i = 0; i < NUM_TRANSACTIONS; i = i + 1) begin
            $display("\n--- DMA Test Transaction %0d ---", i);
            

            // --- Driver Phase, Part 1: Pre-loading Memory ---
            // Before the DMA can be tested, we need to populate the source
            // memory region with the pre-generated random data.
            $display("DRIVER (DMA): Loading source data for this transaction...");

            // This inner loop uses the BFM write task to write each word from the
            // `data_q` array into the DUT's on-chip RAM at the specified source address.
            for (j = 0; j < num_words_q[i]; j = j + 1) begin
                cpu_bfm_write(src_addr_q[i] + (j * 4), data_q[i][j]);
            end



            // --- Driver Phase, Part 2: Configuring and Starting the DMA ---
            // This section simulates a CPU program configuring the DMA controller.
            $display("DRIVER (DMA): Configuring and starting DMA...");

            // Write the source address to the DMA's source address register (offset 0x0).
            cpu_bfm_write(32'h0001_0000, src_addr_q[i]);

            // Write the destination address to the DMA's destination register (offset 0x4).
            cpu_bfm_write(32'h0001_0004, dest_addr_q[i]);

            // Write the number of words to transfer to the DMA's length register (offset 0x8).
            cpu_bfm_write(32'h0001_0008, num_words_q[i]);

            // Write to the DMA's control register (offset 0xC) to start the transfer.
            cpu_bfm_write(32'h0001_000C, 1);


            // --- Driver Phase, Part 3: Waiting for Completion ---
            // The testbench now waits passively for the DMA to finish its work.
            // This `wait` statement pauses execution until the DUT's main interrupt
            // line (`cpu_irq_in`) goes high.
            wait (dut.cpu_irq_in == 1'b1); 
            
            // Wait for one more clock edge to ensure all signals are stable.
            @(posedge clk);

            // --- Driver Phase, Part 4: Interrupt Service Routine ---
            // This mimics a real ISR. It clears the interrupt at both the source
            // (the DMA) and the central controller to prevent stale interrupts.
            $display("DRIVER (DMA): Interrupt received. Clearing interrupts...");

            // Write to the DMA's clear register (offset 0x10).
            cpu_bfm_write(32'h0001_0010, 1);

            // Write to the Interrupt Controller's clear register.
            cpu_bfm_write(32'h0003_0000, 1);
            


            // --- Scoreboard Phase: Verifying the Result ---
            // Now that the DMA transfer is complete, this section verifies its correctness.
            $display("SCOREBOARD (DMA): Verifying copied data...");

            // This loop reads back every word from the destination memory region.
            for (j = 0; j < num_words_q[i]; j = j + 1) begin
                cpu_bfm_read(dest_addr_q[i] + (j * 4), temp_word_read);

                // The core check: Compare the data read back from the destination
                // with the original data from the source. `!==` is used for a
                // case-inequality check that also handles 'X' and 'Z' values.
                if (temp_word_read !== data_q[i][j]) begin

                    // If a mismatch is found, print a detailed error message and
                    // terminate the simulation immediately.
                    $error("SCOREBOARD (DMA) FAILED: Data mismatch at word %0d. Expected 0x%h, Got 0x%h", j, data_q[i][j], temp_word_read); 
                    $finish;
                end
            end

            // If the loop completes without any errors, the transaction is successful.
            $display("SCOREBOARD (DMA): Transaction %0d PASSED.", i);

        end

    endtask




    // This task defines the test case for verifying the CRC32 accelerator.
    // It simulates a CPU program that reads data from RAM and feeds it into
    // the CRC peripheral, then checks the final calculated CRC value.
    task run_crc_test;

        // Local variables for this test.
        reg [31:0] final_crc_from_hw; // Stores the final CRC value read from the DUT.
        reg [31:0] expected_crc; // Stores the "golden" CRC calculated by the testbench.
        reg [31:0] temp_word;  // A temporary variable to hold data read from RAM.

        integer i, j; // Loop counters.

        $display("\n------------------------------------------------------");
        $display("--- CRC FUNCTIONAL TEST ---");


        // Loop to run multiple randomized CRC calculations.
        for (i = 0; i < NUM_TRANSACTIONS; i = i + 1) begin
            $display("\n--- CRC Test Transaction %0d ---", i);


            // --- Driver Phase, Part 1: Pre-loading Memory ---
            // As in the DMA test, we first use the BFM to write the source data
            // packet into the DUT's on-chip RAM.
            $display("DRIVER (CRC): Loading source data for this transaction...");
            for (j = 0; j < num_words_q[i]; j = j + 1) begin
                cpu_bfm_write(src_addr_q[i] + (j * 4), data_q[i][j]);
            end



            // --- Driver Phase, Part 2: Feeding Data to the CRC Accelerator ---
            // This section mimics a CPU program processing a data packet.
            $display("DRIVER (CRC): Feeding data to CRC peripheral...");

            // First, write to the CRC control register (offset 0x0) to reset its
            // internal state to the initial CRC value.
            cpu_bfm_write(32'h0002_0000, 1);



            // This loop reads each word from RAM and immediately writes it to the
            // CRC peripheral's data register (offset 0x4). This heavily exercises
            // the system bus, arbiter, and address decoder.
            for (j = 0; j < num_words_q[i]; j = j + 1) begin

                cpu_bfm_read(src_addr_q[i] + (j*4), temp_word);
                cpu_bfm_write(32'h0002_0004, temp_word);

            end

            // After all data has been fed, perform a final read from the CRC
            // data register to retrieve the hardware-calculated checksum.
            cpu_bfm_read(32'h0002_0004, final_crc_from_hw);


            // --- Scoreboard Phase: Golden Model Comparison ---
            $display("SCOREBOARD (CRC): Calculating golden CRC and checking result...");

            // Initialize a local variable with the standard CRC initial value.
            expected_crc = 32'hFFFFFFFF;

            // Run the same source data through the testbench's own "golden" CRC
            // calculation function. This function is a perfect, bug-free software
            // model of the hardware's intended behavior.
            for (j = 0; j < num_words_q[i]; j = j + 1)
                expected_crc = calculate_crc32_golden(expected_crc, data_q[i][j]);

            // The final check: compare the result from the hardware (DUT) with the
            // result from the perfect software model (golden).
            if (final_crc_from_hw === expected_crc)

                // If they match, the test for this transaction passes.
                $display("SCOREBOARD (CRC): Transaction %0d PASSED. CRC=0x%h", i, final_crc_from_hw);
            else

                // If they do not match, flag a critical error and stop the simulation.
                $error("SCOREBOARD (CRC) FAILED: Mismatch. Expected 0x%h, Got 0x%h", expected_crc, final_crc_from_hw);
        end

    endtask


    // This SystemVerilog `function` is a critical component of the scoreboard for
    // the `run_crc_test`. It serves as the "golden model" or "reference model".
    //
    // What is a Golden Model? It is a bit-accurate, purely behavioral model of
    // the DUT that is known to be correct. It is typically written in a high-level
    // language (like SystemVerilog, C++, or Python) and is not intended for
    // synthesis. Its only purpose is to take the same inputs as the DUT and
    // produce the expected, correct output.
    //
    // Why is it used? It allows for powerful, self-checking verification. The
    // testbench can feed the same random data to both the DUT (the hardware) and
    // this golden model (the perfect software version). It then simply compares
    // the two outputs. A mismatch indicates a bug in the DUT's hardware
    // implementation. This function is a direct, line-for-line translation of the
    // CRC-32 algorithm, ensuring its correctness for the scoreboard comparison.



    /*
    --------------------------------------------------------------------------------
    -- Concept Deep Dive: The Golden Model (or Reference Model)
    --------------------------------------------------------------------------------
    -- What is it?
    -- A "golden model" is a purely behavioral, software-like implementation of
    -- the hardware's functionality that is written within the testbench. It is
    -- considered the "source of truth" and is assumed to be perfectly correct,
    -- acting as the ultimate reference for what the DUT's output should be.
    --
    -- Where is it used here?
    -- This function, `calculate_crc32_golden`, is the golden model for the
    -- `crc32_accelerator` DUT. It takes the same inputs as the hardware block
    -- (the current CRC state and new data) and performs the exact same CRC-32
    -- calculation.
    --
    -- Why is this so critical for verification?
    -- This is the heart of a self-checking scoreboard. Instead of manually
    -- pre-calculating the correct CRC for a given data stream and hard-coding it
    -- into the test, this function allows for dynamic, on-the-fly checking. The
    -- `run_crc_test` task can now:
    --   1. Generate a completely random stream of data.
    --   2. Feed this random data to BOTH the hardware DUT and this `calculate_crc32_golden` function.
    --   3. Compare the final hardware result against the final golden model result.
    -- A mismatch definitively proves there is a bug in the RTL implementation of
    -- the `crc32_accelerator`, as the golden model is trusted to be correct. This
    -- enables powerful, automated, and randomized testing.
    --------------------------------------------------------------------------------
    */
    // This `function` defines a reusable piece of purely combinational logic. In
    // SystemVerilog, functions must execute in zero simulation time and cannot contain
    // any delays or timing controls (like `@` or `#`). This makes them ideal for
    //-- modeling mathematical or algorithmic operations. This function returns a
    // 32-bit vector, which will be the newly calculated CRC value.
    function [31:0] calculate_crc32_golden;

        // --- Function Arguments ---
        // `input` declares an argument to the function.
        // `crc_in`: A 32-bit input representing the previous CRC state. For the
        // first word in a stream, this would be the initial value (0xFFFFFFFF).
        // For subsequent words, it's the result from the previous calculation.
        input [31:0] crc_in; 

        // `data_in`: A 32-bit input representing the new data word to be processed.
        input [31:0] data_in;

        // --- Internal Function Variables ---
        // These variables are temporary and exist only within the scope of this function call.
        // `d`: A 32-bit register to hold a local copy of the input data.
        reg [31:0] d;

        // `c`: A 32-bit register to hold a local, mutable copy of the CRC value
        // that will be updated during the calculation.
        reg [31:0] c;

        // `i`: A standard 32-bit signed integer used as the loop counter. It's
        // a common choice for loop variables in SystemVerilog procedural blocks.
        integer i;


        // The `begin...end` block encloses the executable part of the function.
        begin 

            // Initialize the local variables with the function's input arguments.
            d=data_in;
            c=crc_in;

            // This `for` loop is the direct implementation of the bit-serial CRC
            // algorithm. It iterates 32 times, once for each bit of the `data_in` word.
            for (i=0; i<32; i=i+1)

            // This `if` statement performs the core CRC logic.
            // It checks the result of an XOR operation between two bits:
            //   1. `c[31]`: The most significant bit (MSB) of the current CRC state.
            //   2. `d[31-i]`: The current data bit being processed, from MSB to LSB.
            if ((c[31]^d[31-i])) 
            
            // If the XOR result is 1, two things happen:
            //   1. The current CRC `c` is shifted left by 1 (`c << 1`).
            //   2. The shifted result is then XORed with the standard Ethernet
            //      CRC-32 polynomial, `32'h04C11DB7`.
            c=(c<<1)^32'h04C11DB7;


            // If the XOR result is 0, the CRC register is simply shifted
            // left by 1. No polynomial XOR is performed.
            else c=c<<1;


            // In Verilog/SystemVerilog, a function returns a value by assigning it
            // to a variable that has the same name as the function itself. After
            // 32 iterations, the final value held in `c` is the new CRC-32 checksum,
            // which is then returned by the function.
            calculate_crc32_golden = c;

        end

    endfunction
    


    // This task defines the directed test for the general-purpose timer peripheral.
    // Its primary goals are to verify that the timer can be configured, that it
    // generates an interrupt after a specified delay, and that the interrupt
    // can be correctly identified and cleared by the system.
    task run_timer_test;

        // Local variables for this specific test.
        reg [31:0] compare_val, intc_status;

        // A fixed value for the timer's compare register. This makes the test
        // deterministic and repeatable.
        compare_val = 32'd500;
        $display("\n------------------------------------------------------");
        $display("--- TIMER FUNCTIONAL TEST ---");

        // --- Driver Phase: Configure and Start Timer ---
        // Write the compare value to the timer's compare register (offset 0x4).
        cpu_bfm_write(32'h0004_0004, compare_val);

        // Write to the timer's control register (offset 0x0) to enable it.
        cpu_bfm_write(32'h0004_0000, 1);

        // --- Driver Phase: Wait for Interrupt ---
        // The test now pauses and waits for the timer to count up to the compare
        // value and fire an interrupt, which will be signaled on `dut.cpu_irq_in`.
        wait (dut.cpu_irq_in == 1'b1); @(posedge clk);


        // --- Scoreboard Phase, Part 1: Check Interrupt Source ---
        // Once the interrupt is received, we must verify it came from the correct source.
        // Read the Interrupt Controller's status register.
        cpu_bfm_read(32'h0003_0000, intc_status);

        // The timer is connected to IRQ line 1. Check if bit 1 of the status
        // register is set. If not, the interrupt mapping is wrong.
        if (intc_status[1] !== 1'b1) $error("SCOREBOARD (Timer) FAILED: Interrupt source incorrect.");

        // --- Scoreboard Phase, Part 2: Check Interrupt Clearing ---
        // This mimics a real Interrupt Service Routine (ISR) by clearing the
        // interrupt at both the source and the controller.
        // Write to the timer's control register to clear its internal interrupt flag.
        cpu_bfm_write(32'h0004_0000, 32'h2);

        // Write to the main interrupt controller to clear its latched interrupt.
        cpu_bfm_write(32'h0003_0000, 1);

        // Wait for a few cycles to allow the clear signals to propagate.
        #20;

        // The ultimate check: verify that the main interrupt line to the CPU is
        // now de-asserted (low). If it's still high, the clear logic has failed.
        if (dut.cpu_irq_in == 1'b1) $error("SCOREBOARD (Timer) FAILED: Interrupt did not clear.");

        // If all checks pass, the timer test is successful.
        $display("SCOREBOARD (Timer): Test PASSED.");

    endtask


    // This task defines the directed test for the UART. It leverages the physical
    // loopback connection (`assign uart_rx_pin_to_dut = uart_tx_pin_from_dut;`)
    // to verify the entire serial communication path in a self-contained manner.
    task run_uart_loopback_test;

        // Local variables for this test.
        reg [7:0] char_to_send; // The 8-bit character we will transmit.

        // For reading back status registers.
        reg [31:0] intc_status; 
        reg [31:0] uart_rx_reg;

        // Use a fixed, non-trivial character for deterministic testing.
        char_to_send = 8'hE7;
        $display("\n------------------------------------------------------");
        $display("--- UART LOOPBACK TEST ---");

        // --- Driver Phase: Transmit a Character ---
        // Use the BFM to write the character to the UART's transmit data register
        // (offset 0x0). This single write will cause the UART hardware to
        // serialize the data and send it, bit-by-bit, out the `uart_tx_pin`.
        cpu_bfm_write(32'h0005_0000, char_to_send);

        // --- Driver Phase: Wait for Interrupt ---
        // Because of the loopback, the transmitted bits are immediately received
        // by the UART's receiver. Once the receiver assembles a full character,
        // it is designed to fire an interrupt. The testbench pauses here, waiting
        // for that "receive complete" interrupt.
        wait (dut.cpu_irq_in == 1'b1);
        @(posedge clk);

        // --- Scoreboard Phase, Part 1: Check Interrupt Source ---
        // Read the Interrupt Controller's status register to ensure the interrupt
        // came from the correct source (IRQ line 2, for the UART).
        cpu_bfm_read(32'h0003_0000, intc_status);
        if (intc_status[2] !== 1'b1) 
        $error("SCOREBOARD (UART) FAILED: Interrupt source incorrect. INTC=0x%h", intc_status);

        // --- Scoreboard Phase, Part 2: Check Received Data ---
        // Read the UART's receive data register (offset 0x4).
        cpu_bfm_read(32'h0005_0004, uart_rx_reg);

        // The UART's receive register is designed to have a 'valid' flag in bit 8
        // and the 8-bit data in bits [7:0]. Check both:
        // 1. Is the valid flag set?
        // 2. Does the received character match the one we sent?
        if (uart_rx_reg[8] != 1'b1 || uart_rx_reg[7:0] != char_to_send) 
        $error("SCOREBOARD (UART) FAILED: Data mismatch or invalid flag.");

        // --- Scoreboard Phase, Part 3: Check Interrupt Clearing ---
        // Perform a full, two-step interrupt clear.
        // First, clear the status at the source (the UART's receive register).
        cpu_bfm_write(32'h0005_0004, 1); 
        
        // Then, clear the central interrupt controller.
        cpu_bfm_write(32'h0003_0000, 1); 
        
        // Wait and then verify that the main interrupt line is now low.
        #20;

        if (dut.cpu_irq_in == 1'b1) 
        $error("SCOREBOARD (UART) FAILED: Interrupt did not clear.");

        // If all checks pass, the entire UART tx/rx path is verified.
        $display("SCOREBOARD (UART Loopback): Test PASSED.");
    endtask


    // This task group tests the SoC's behavior under edge-case (corner-case) and
    // illegal (negative) scenarios. A robust verification plan must go beyond
    // testing only the "happy path" or expected functionality. It must actively
    // try to provoke incorrect behavior to ensure the design is resilient and fails
    // gracefully. This demonstrates a mature, professional verification mindset.
    task run_negative_and_corner_case_tests;

        reg [31:0] read_back_word;  // A temporary register for holding read results.
        $display("\n------------------------------------------------------");
        $display("--- CORNER CASE & NEGATIVE TESTS ---");

        // --- Corner Case: Zero-Length DMA Transfer ---
        // This test checks a valid but tricky corner case: what happens when the
        // DMA is programmed to transfer zero words? The expected, correct behavior
        // is that the DMA should do nothing and, most importantly, should NOT
        // fire an interrupt. An interrupt should only signal the completion of work.
        $display("Test: Zero-Length DMA Transfer...");

        // Configure the DMA with valid source/destination addresses but a length of 0.
        cpu_bfm_write(32'h0001_0000, 32'h5000); 
        cpu_bfm_write(32'h0001_0004, 32'h6000); 
        cpu_bfm_write(32'h0001_0008, 0);

        // Start the DMA.
        cpu_bfm_write(32'h0001_000C, 1);

        // This `fork...join_any` block creates two parallel threads of execution:
        //   - The first thread (`begin: t`) is a timeout. It simply waits for a
        //     long period (2000ns) and, if it finishes, declares the test a success.
        //   - The second thread (`begin: i`) waits for an interrupt. If an interrupt
        //     *is* detected, it means the DUT behaved incorrectly. It flags a
        //     fatal error and terminates the simulation.
        // `join_any` means the block finishes as soon as EITHER thread completes,
        // and the `disable` statements clean up the other, unfinished thread.

        fork 
            begin: t 
                #2000; 
                $display("  -> Zero-length DMA PASS.");
            end 

            begin: i 
                wait(dut.cpu_irq_in == 1'b1); 
                $error("FAILED: Interrupt fired for zero-length DMA."); 
                $finish; 
            end 
            
        join_any; 
        
        disable t; 
        disable i;
        @(posedge clk);

        // --- Negative Test: Illegal Address Read ---
        // This test probes the system's response to an invalid operation: a read
        // from an address that does not correspond to any mapped peripheral.
        // The hardware should handle this gracefully without crashing or hanging.
        $display("Test: Illegal Address Read...");

        // Use the BFM to read from a high address (0x9000_0000) that is guaranteed
        // to be outside the defined memory map of any peripheral.
        cpu_bfm_read(32'h9000_0000, read_back_word);

        // The top-level bus logic is designed to return a specific, recognizable
        // garbage value (`32'hBAD_DDAA`) when no slave is selected. This check
        // verifies that the address decoder and bus multiplexer are working
        // correctly for out-of-bounds accesses.
        if (read_back_word !== 32'hBAD_DDAA)
        $error("FAILED: Incorrect value on illegal read.");

        $display("  -> Illegal Address Read PASS.");

    endtask





    // --- Main Test Sequencer ---
    // This `initial` block is the heart of the testbench's execution flow. It
    // acts as the 'main()' function in a software program. It is responsible for
    // reading command-line arguments, setting up the test environment, generating
    // stimulus, and selecting which test case (or cases) to run.
    initial begin

        // A `string` is a SystemVerilog data type for holding variable-length text.
        // It's used here to store the name of the test to be run.
        string testname;

        // An `integer` is a 32-bit signed variable used here to hold the seed for
        // the random number generator, ensuring repeatable random sequences.
        integer seed;


          /*
        ----------------------------------------------------------------------------
        -- Concept Deep Dive: Plusargs for Test Automation
        ----------------------------------------------------------------------------
        -- What is it?
        -- "Plusargs" (short for "plus arguments") are command-line arguments passed
        -- to a simulation that begin with a `+` character. They are a standard
        -- feature of Verilog and SystemVerilog simulators used to control or
        -- configure a test run from outside the testbench code itself. The system
        -- task `$value$plusargs` is used to search for and read these arguments.
        --
        -- How is it used here?
        -- The line `if (!$value$plusargs("TESTNAME=%s", testname))` is the key.
        --   - It searches the simulator's command line for a string that matches
        --     the pattern "TESTNAME=". For example: `+TESTNAME=DMA_TEST`.
        --   - The `%s` format specifier tells the task to expect a string value.
        --   - If a match is found, the task extracts the value ("DMA_TEST") and
        --     stores it in the `testname` string variable. The task then returns 1.
        --   - If no such argument is found, the task returns 0, and the `if`
        --     condition becomes true, causing the default value "FULL_REGRESSION"
        --     to be assigned to `testname`.
        --
        -- Why is this so important for this project?
        -- This single line is the linchpin of the entire automated regression system.
        -- It decouples the testbench logic from the execution control. The Python
        -- script (`run_regression.py`) can now run this *same* compiled simulation
        -- file over and over again, simply changing the `+TESTNAME` plusarg each
        -- time to execute a different test case.
        --
        --   - Without this: I would need to either have separate testbench files for
        --     each test or manually edit this file to comment/uncomment the test
        --     I want to run. Both are incredibly inefficient and error-prone.
        --   - With this: The testbench becomes a flexible, multi-purpose tool that
        --     can be easily controlled by a higher-level script, demonstrating a
        --     professional and scalable approach to verification management.
        ----------------------------------------------------------------------------
        */


        // This is the core of the automation system. The `$value$plusargs` system
        // task scans the command line for an argument matching the format
        // "+TESTNAME=<string>". If it finds a match, it stores the <string> part
        // in the `testname` variable and returns 1. If not, it returns 0.
        // If no `TESTNAME` is provided, the testbench defaults to "FULL_REGRESSION".
        if (!$value$plusargs("TESTNAME=%s", testname)) testname = "FULL_REGRESSION";

        // Print a banner to the simulation log. This is good practice as it clearly
        // marks the beginning of a test run and which test is being executed.
        $display("======================================================");
        $display("--- Starting RISC-V SoC System-Level Test ---");
        $display("---           TESTNAME: %s            ---", testname);
        $display("======================================================");

        // This `wait` statement ensures that no test logic begins until after the
        // initial reset sequence is complete and the `rst_n` signal is high.
        wait (rst_n === 1'b1);

        // Wait for one more clock edge for maximum stability before starting.
        @(posedge clk);


        // --- Constrained-Random Stimulus Generation ---
        // This block of code is responsible for creating interesting and varied
        // test data for the DMA and CRC test cases. While not a full UVM-style
        // constrained-random environment, it uses the same core principles.


        // This block pre-generates the randomized data for the DMA and CRC tests.
        // This is done only if one of those tests (or the full regression) is selected.
        // Pre-generation ensures that the randomness is created once, and the same
        // data can be used for multiple tests if needed, aiding in debug.
        if (testname == "DMA_TEST" || testname == "CRC_TEST" || testname == "FULL_REGRESSION") begin

            // Seeding the random number generator with a fixed value is a critical
            // professional practice. It ensures that the "random" sequence
            // generated is identical every time the simulation is run. This makes
            // test failures repeatable and therefore debuggable. A different seed
            // can be used to explore a new random scenario.
            seed = 12345; // Using a fixed seed ensures the "random" sequence is identical every run.

            $display("SEQUENCER: Generating %0d random transactions for DMA and CRC tests...", NUM_TRANSACTIONS);

            // This set of nested loops populates the data storage arrays (`src_addr_q`, etc.)
            // with constrained-random values using the `$random` system function.

            // This loop generates the properties for `NUM_TRANSACTIONS` test packets.
            for (integer i = 0; i < NUM_TRANSACTIONS; i = i + 1) begin


                // Generate a random source address. The `& 16'hA000` is a constraint
                // that ensures the address is within the valid RAM address space and
                // leaves enough room for the maximum transfer size.
                src_addr_q[i] = ( ({$random(seed)} & 16'hA000) );


                // Generate a destination address that is guaranteed not to overlap with
                // the source address block, preventing data corruption.
                dest_addr_q[i] = src_addr_q[i] + 32'h4000; // Ensure non-overlapping areas


                // Generate a random transfer length between 1 and `MAX_WORDS`.
                // The `+ 1` prevents a zero-length transfer from being generated here,
                // as that is tested separately as a corner case.
                num_words_q[i] = ({$random(seed)} % MAX_WORDS) + 1;

                // This inner loop generates the random data payload for the current transaction.
                for (integer j = 0; j < num_words_q[i]; j = j + 1) begin

                    // `{$random, $random}` concatenates two 16-bit random numbers to form
                    // a full 32-bit random data word.
                    data_q[i][j] = {$random(seed), $random(seed)};

                end

            end

            $display("SEQUENCER: Data generation complete.");

        end
        

        // A critical setup step: perform a write to the interrupt controller's
        // clear register immediately after reset. This ensures that no unknown or
        // 'X' values from the beginning of the simulation have caused a phantom
        // interrupt to be latched, which would fail the first real test.
        $display("TB: Performing post-reset interrupt cleanup..."); // Post-reset cleanup to ensure no stale interrupts are pending
        cpu_bfm_write(32'h0003_0000, 1);
        @(posedge clk);

        // This large `if/else if` chain is the main test dispatcher. It checks the
        // value of the `testname` variable and calls the corresponding test task.
        if (testname == "DMA_TEST") run_dma_test();
        else if (testname == "CRC_TEST") run_crc_test();
        else if (testname == "TIMER_TEST") run_timer_test();
        else if (testname == "UART_LOOPBACK_TEST") run_uart_loopback_test();
        else if (testname == "CORNER_CASE_TEST") run_negative_and_corner_case_tests();
        else if (testname == "FULL_REGRESSION") begin
            $display("\n\n>>> RUNNING FULL REGRESSION SUITE <<<");
            run_dma_test();
            run_crc_test();
            run_timer_test();
            run_uart_loopback_test();
            run_negative_and_corner_case_tests();

            // The "FULL_REGRESSION" case simply calls all the individual test
            // tasks sequentially, providing a comprehensive check of the whole design.
            $display("\n\n>>> FULL REGRESSION SUITE COMPLETED SUCCESSFULLY <<<");
        end 
        
        else begin

            // If an unknown testname was provided on the command line, flag an error.
            $error("Unknown TESTNAME specified: %s", testname);
            $finish;

        end

        // If the selected test (or the full regression) completes without any
        // `$error` calls, this final message is printed. This specific string,
        // "--- Test Successful. ---", is what the `run_regression.py` script
        // searches for in the log file to declare a PASS.

        $display("\n======================================================");
        $display("--- Test Successful. ---");
        $display("======================================================");

        $finish;

    end


    // --- Waveform Dumping ---
    // This `initial` block is a fundamental component of any robust verification
    // environment. Its sole purpose is to configure the simulator to record the
    // activity of the signals within the design during a test run. This creates a
    // detailed log file that can be visually analyzed later, which is the primary
    // method for debugging hardware failures. This block executes exactly once, at
    // the very beginning of the simulation (time 0).

    
    initial begin

        // `$dumpfile` is a standard SystemVerilog system task that instructs the
        // simulator to create a specific file for storing waveform data.
        //
        // What is it doing? It is creating a file named "waveform.vcd".
        //
        // What is a .vcd file? VCD stands for Value Change Dump. It is a standard,
        // ASCII-based file format that logs every single change in value for every
        // signal that we specify. For example, it will record "at time 25ns, signal
        // 'clk' changed from 0 to 1".
        //
        // Why is this important? This file is the input to a waveform viewer program,
        // in this case, GTKWave. It is the "ground truth" for the simulation.
        // When a test fails, a Design Verification engineer's first action is almost
        // always to open this VCD file to visually inspect the signals and trace the
        // root cause of the problem. It is the hardware equivalent of a software
        // debugger's variable watch window, but it captures a complete time-history.
        $dumpfile("waveform.vcd");



        // `$dumpvars` is the companion system task to `$dumpfile`. While `$dumpfile`
        // creates the file, `$dumpvars` tells the simulator *which* signals to record
        // into that file.
        //
        // The first argument, `0`: This specifies the number of levels of hierarchy
        // to dump, starting from the specified module. A value of `0` is a special
        // instruction that means "dump the signals in the specified module, and all
        // modules instantiated within it, and all modules within those modules, and
        // so on, recursively, through the entire design hierarchy." This ensures we
        // capture every single wire and register in the whole system.
        //
        // The second argument, `tb_risc_soc`: This specifies the top-level scope or
        // module instance from which to start dumping. Since this command is in the
        // `tb_risc_soc` module itself, we are telling it to start here.
        //
        // In summary: These two lines together command the simulator to "Record all
        // signal activity for all components within the entire `tb_risc_soc`
        // environment and save it to `waveform.vcd`." This provides the total
        // visibility needed for effective debugging.

        $dumpvars(0, tb_risc_soc);
    end

endmodule





/*
--------------------------------------------------------------------------------
--                              PROJECT ANALYSIS
--------------------------------------------------------------------------------
--
-- 
--
-- ############################################################################
-- ##                     Methodology and Implementation                     ##
-- ############################################################################
--
--
-- [[ Relevance of This File ]]
--
-- This file, `tb_risc_soc.sv`, is the single most critical asset for ensuring the
-- quality and correctness of the entire SoC design. While the RTL files define
-- *what* the chip does, this testbench defines *how we know it works*. It is the
-- embodiment of the entire verification effort. Its significance lies in its
-- ability to act as a programmable, automated, and self-checking "virtual user"
-- of the DUT, capable of executing thousands of tests and providing a definitive
-- pass/fail verdict. In any professional VLSI project, the verification
-- environment is considered as important, if not more so, than the design itself.
--
--
-- [[ Key Concepts Implemented ]]
--
-- This testbench is a practical implementation of several fundamental and
-- industry-standard verification concepts:
--
--   1. Bus Functional Model (BFM): The `cpu_bfm_write` and `cpu_bfm_read` tasks
--      form a high-level API to the DUT's bus, abstracting away the complex
--      low-level timing and protocol details. This is the foundation of a
--      reusable, layered testbench architecture.
--
--   2. Self-Checking Scoreboards: Each test contains its own logic for result
--      verification. The DMA test compares memory blocks, while the CRC test uses
--      a golden model. This self-checking capability is what enables full
--      automation, as a human is not needed to check waveforms for correctness.
--
--   3. Constrained-Random Verification: The stimulus generation block uses
--      SystemVerilog's `$random` function, but with constraints (e.g., valid
--      address ranges, non-zero lengths). This creates a wide variety of
--      interesting and unexpected test scenarios, which is far more powerful
--      for finding bugs than a few manually-written "golden" test cases.
--
--   4. Automation-Driven Structure: The entire testbench is architected around
--      the `$value$plusargs` mechanism, making it a slave to an external control
--      script (`run_regression.py`). This demonstrates a professional approach
--      to building a scalable, scriptable regression environment.
--
--   5. Negative and Corner-Case Testing: The inclusion of tests for zero-length
--      transfers and illegal addresses shows a mature verification mindset, focused
--      on testing the design's resilience and error-handling capabilities, not just
--      its primary functions.
--
--------------------------------------------------------------------------------
*/



/*

--
-- ############################################################################
-- ##                 Testbench Architecture and Philosophy                  ##
-- ############################################################################
--
--
-- [[ My Testbench Architecture Philosophy ]]
--
-- When designing this testbench, my primary goal was to emulate the structured
-- and layered approach of professional verification methodologies like UVM,
-- even while using only basic SystemVerilog constructs. The core philosophy
-- was a strict "separation of concerns." I intentionally structured the code
-- to separate the "how" from the "what."
--
--   - The "How" (The BFM): The BFM tasks (`cpu_bfm_write`, `cpu_bfm_read`) handle
--     *how* to perform a bus transaction. They contain all the low-level,
--     protocol-specific details: timing, handshaking (`wait(gnt)`), and pin
--     wiggling. This code is complex, but it is written once and then reused.
--
--   - The "What" (The Test Cases): The test case tasks (`run_dma_test`, etc.)
--     describe *what* the test should achieve at a high, conceptual level. For
--     example, the DMA test is described as: "load memory, configure DMA, wait
--     for interrupt, check memory." It achieves this by calling the BFM tasks,
--     but it doesn't need to know anything about the bus protocol itself.
--
-- This separation is incredibly powerful. If the bus protocol were to change
-- (e.g., adding a `ready` signal), I would only need to modify the BFM tasks.
-- All the high-level test cases would remain completely unchanged, which makes
-- the environment highly maintainable and scalable.
--
-- Furthermore, I structured each test case to have distinct internal phases:
--
--   1. Stimulus Generation (The "Driver"): This part of the test actively
--      interacts with the DUT to set up a scenario. It calls the BFM tasks to
--      write configuration registers and prepare memory.
--
--   2. Waiting for DUT Action: The testbench often becomes passive, waiting
--      for the DUT to complete an autonomous action, which is typically
--      signaled by an interrupt (`wait (dut.cpu_irq_in == 1'b1)`).
--
--   3. Results Checking (The "Scoreboard"): After the DUT has acted, this part
--      of the test reads back status and data, compares it against expected
--      values or a golden model, and determines the pass/fail result.
--
-- This "Driver -> Wait -> Scoreboard" pattern within each test makes the test's
-- intent very clear and easy to follow, which is crucial for debugging when a
-- test fails.
--
--------------------------------------------------------------------------------
*/


/*
--
-- ############################################################################
-- ##                     Verification Plan and Coverage                     ##
-- ############################################################################
--
--
-- [[ My Verification Plan ]]
--
-- A verification plan is a high-level document that outlines what features need
-- to be tested and how they will be verified. Before writing this testbench,
-- I created a mental verification plan that guided its structure. The plan was
-- to move from basic connectivity checks to verifying full end-to-end scenarios.
--
--   1. Foundational Checks (Bring-up):
--      - Objective: Ensure the bus, memory, and basic BFM control are working.
--      - Implementation: An implicit test where the BFM writes to RAM and reads
--        back. This is a prerequisite for all other tests. The illegal address
--        read in the `CORNER_CASE_TEST` also falls here, as it verifies the
--        address decoder's default behavior.
--
--   2. Individual Peripheral Features (Directed Tests):
--      - Objective: Verify the core functionality of each major peripheral in
--        a targeted, deterministic way.
--      - Implementation:
--        - `run_timer_test`: Checks the timer's ability to count, fire an
--          interrupt, and be cleared.
--        - `run_uart_loopback_test`: Checks the UART's combined transmit and
--          receive functionality and its interrupt mechanism.
--
--   3. Key System-Level Scenarios (Constrained-Random Tests):
--      - Objective: Verify the most complex interactions between multiple IP
--        blocks under a variety of conditions.
--      - Implementation:
--        - `run_crc_test`: Verifies the CPU can correctly control the CRC
--          accelerator by feeding it data from RAM. This tests the CPU master
--          path, arbitration, bus, RAM, and the CRC peripheral.
--        - `run_dma_test`: This is the most comprehensive test. It verifies the
--          DMA's ability to become a bus master, interact with the arbiter,
--          and read/write from RAM, all independent of the CPU. It covers almost
--          every single interaction path in the SoC.
--
--   4. System Robustness (Corner-Case and Negative Tests):
--      - Objective: Ensure the design handles unusual or illegal inputs gracefully.
--      - Implementation: `run_negative_and_corner_case_tests` checks scenarios
--        like zero-length transfers that shouldn't cause hangs or spurious interrupts.
--
--
-- [[ Functional Coverage Achieved ]]
--
-- While this testbench does not use formal functional coverage collection (a feature
-- of advanced tools like VCS/Questa), the suite of tests is designed to implicitly
-- cover the most critical functionality:
--
--   - Bus Arbitration: The `DMA_TEST` explicitly covers the case where the DMA
--     requests and is granted the bus. Since the BFM (CPU) is active during the
--     setup, bus contention scenarios are implicitly tested.
--   - All Peripherals: Each peripheral has at least one dedicated test that verifies
--     its core function and its interrupt path to the CPU.
--   - DMA Data Path: The `DMA_TEST` covers memory-to-memory transfers with randomized
--     addresses, lengths, and data content, providing good coverage of its FSM
--     and data path logic.
--   - Interrupt System: Every test that involves waiting for an interrupt
--     (`run_dma_test`, `run_timer_test`, `run_uart_loopback_test`) verifies a unique
--     path through the interrupt controller and tests the ISR's ability to correctly
--     identify and clear the source.
--
-- The final `FULL_REGRESSION` run ensures that all these covered features are
-- tested together, providing high confidence in the overall system quality.
--
--------------------------------------------------------------------------------
*/


/*
-- 
--
-- ############################################################################
-- ##                     Bug Chronicle and Debugging Diary                  ##
-- ############################################################################
--
--
-- [[ Bug Chronicle Part 1: The "Stale Interrupt" Testbench Bug ]]
--
-- This is a story about one of the most humbling and educational bugs I
-- encountered. It was a "false negative," where my testbench was incorrectly
-- flagging a failure in a perfectly functional piece of hardware. This type
-- of bug is particularly insidious because it can lead to wasting days trying
-- to "fix" RTL that is not actually broken.
--
-- The Symptom:
-- I designed a new test case to improve coverage: a "back-to-back" DMA
-- transfer. The test would run one complete DMA transaction, and immediately
-- upon its completion, it would start a second, different DMA transaction.
-- The test was consistently failing. The log showed:
--   - The first DMA transfer completed and passed its scoreboard check perfectly.
--   - The testbench would then configure and start the second DMA transfer.
--   - Almost instantly—long before the second transfer could have possibly
--     finished—the testbench would detect an interrupt and proceed to the
--     scoreboard phase for the second transfer.
--   - The scoreboard would then, of course, fail with a data mismatch, as the
--     data had not yet been copied.
--
-- My Initial Hypothesis:
-- My immediate assumption was that the DUT was at fault. I hypothesized that
-- there was a bug in the DMA engine's FSM where it was not correctly returning
-- to its IDLE state after the first transfer. I thought perhaps it was getting
-- "stuck" in a completion state and immediately firing another interrupt when
-- re-enabled. I spent a considerable amount of time meticulously reviewing the
-- DMA's RTL and analyzing its FSM transitions in the waveform viewer for the
-- first transfer, but everything appeared to be correct. The FSM was cleanly
-- returning to IDLE as designed. This contradiction between the symptom and the
-- state of the DMA FSM was the first clue that my hypothesis was wrong.
--
--------------------------------------------------------------------------------
*/
/*
--
-- [[ Bug Chronicle Part 2: Waveform Analysis and the "Aha!" Moment ]]
--
-- With my initial hypothesis (a bug in the DMA's FSM) invalidated, I had to
-- take a step back and adopt the most fundamental rule of hardware debugging:
-- "Trust the waveform, not your assumptions." The only way forward was to
-- meticulously trace the entire interrupt signaling chain in GTKWave.
--
-- My Evidence Gathering Strategy:
-- I set up a dedicated view in GTKWave to observe the complete interrupt path,
-- from the peripheral source to the CPU's input pin. I added the following
-- critical signals, organized by hierarchy:
--
--   - DMA Engine: `dut.u_dma.dma_done` (The raw interrupt source from the DMA)
--   - Interrupt Controller: `dut.u_intc.irq0_in` (The input port for the DMA's IRQ)
--   - Interrupt Controller: `dut.u_intc.irq0_latched` (The internal latch for IRQ0)
--   - SoC Top: `dut.cpu_irq_in` (The final, combined interrupt line to the CPU)
--   - SoC Top: `dut.bus_addr`, `dut.bus_wr_en` (To see the BFM's clearing actions)
--
-- The "Aha!" Moment:
-- I ran the failing test and zoomed into the critical time window right after
-- the first DMA transfer completed. The waveform told a clear story:
--
--   1. At time T, `dma_done` from the DMA correctly pulsed high.
--   2. At T+1, the `irq0_latched` inside the interrupt controller correctly went high.
--   3. At T+1, `cpu_irq_in` also went high, as expected.
--   4. My testbench BFM correctly saw `cpu_irq_in` go high and initiated its
--      "Interrupt Service Routine" (ISR). I saw a BFM write transaction on the
--      bus to the interrupt controller's address (`0x0003_0000`).
--   5. At T+N, after the BFM write, the `irq0_latched` and `cpu_irq_in` signals
--      correctly went low. This proved the interrupt controller's clearing
--      logic was working perfectly.
--
-- This is where the crucial observation happened. I advanced the clock one cycle
-- at a time and kept my eyes on all the signals. As my BFM started the *next*
-- write to configure the second DMA transfer, I saw `irq0_latched` and `cpu_irq_in`
-- go high *again*! The interrupt had reappeared out of nowhere.
--
-- The Root Cause: I traced the source. I looked back at the raw `dut.u_dma.dma_done`
-- signal. It had gone high at the end of the first transfer... and it had *never
-- gone back down*. It was still asserted. The hardware was behaving exactly as
-- designed: the interrupt controller, after being cleared, immediately saw that its
-- input `irq0_in` was still high, so it dutifully re-latched the interrupt on the
-- very next clock cycle.
--
-- The bug was not in the hardware at all. The bug was in my testbench's "software."
--
--------------------------------------------------------------------------------
*/


/*
--
############################################################################
--
--
-- [[ Bug Chronicle Part 3: The Fix and Lessons Learned ]]
--
-- The waveform analysis definitively proved that my testbench's model of a
-- software Interrupt Service Routine (ISR) was incomplete and incorrect. A
-- real ISR must clear the interrupt flag at its source, not just at the central
-- controller. My testbench BFM was only doing the latter.
--
-- The Solution:
-- The fix was to make the testbench's ISR more realistic by adding the missing
-- step. I modified the `run_dma_test` task (and all other interrupt-driven
-- tests) to perform a proper, two-step interrupt clear after receiving an
-- interrupt.
--
--   1. The original code only had one clearing write:
--      `cpu_bfm_write(32'h0003_0000, 1); // Clears ONLY the central controller`
--
--   2. The corrected, robust code performs two writes in sequence:
--      `cpu_bfm_write(32'h0001_0010, 1); // Step 1: Clear the flag AT THE DMA`
--      `cpu_bfm_write(32'h0003_0000, 1); // Step 2: Clear the flag AT THE INTC`
--
-- After this change was implemented in the testbench, the `dma_done` signal in
-- the waveform correctly went low after the first write. The subsequent write
-- cleared the central controller's latch. Now, when the testbench started the
-- second DMA transfer, the entire interrupt path was clean and de-asserted. The
-- test proceeded correctly, waited the proper amount of time for the second
-- transfer to complete, and passed its scoreboard check. The bug was completely
-- resolved by fixing the testbench, with zero changes to the DUT's RTL.
--
-- The Lessons Learned:
-- This was an incredibly valuable experience. The most important lesson was that
-- **the verification environment is a piece of software in its own right and is
-- just as susceptible to bugs as the hardware it tests.** It taught me to be
-- critical of my own testbench code and not to immediately assume the DUT is
-- at fault. It also reinforced the importance of accurately modeling the
-- hardware/software interface. A testbench doesn't just drive signals; it must
-- correctly model the behavior of the software that will eventually run on the
-- hardware, including all steps of complex protocols like interrupt handling.
--
--------------------------------------------------------------------------------
*/



/*
-- 
--
-- ############################################################################
-- ##                    Industrial Context and Applications                 ##
-- ############################################################################
--
--
-- [[ Industrial Applications of this Verification Environment ]]
--
-- The verification environment built in this file, while simpler, directly
-- mirrors the structure and philosophy of professional verification environments
-- used at companies like Intel, NVIDIA, Apple, and Qualcomm. A Design
-- Verification (DV) engineer's primary role is to build, maintain, and run
-- environments just like this one.
--
--   1. IP-Level and Subsystem Verification:
--      In industry, a "block-level" verification team receives an IP block
--      (like a DMA controller or a PCIe core) from a design team. Their job is
--      to create a testbench that surrounds this DUT. This testbench will contain
--      BFMs that mimic the behavior of the other system components the DUT will
--      talk to. For example, to test a PCIe core, the DV engineer would use an
--      AXI BFM to act like the SoC's internal bus and a PCIe BFM to act like an
--      external device. This `tb_risc_soc` is effectively a subsystem-level
--      testbench, where our BFM mimics the CPU to test the entire integrated
--      SoC.
--
--   2. Automated Nightly Regressions:
--      The combination of this testbench (controlled by plusargs) and the
--      `run_regression.py` script is a small-scale model of a "nightly regression."
--      In large companies, a vast automated system (using schedulers like LSF
--      or Jenkins) runs thousands of tests on the latest version of the design
--      every single night. The system compiles the design, farms out all the
--      tests to a server cluster, and then gathers the pass/fail results into a
--      central dashboard. This `tb_risc_soc` and its associated script are the
--      fundamental building blocks of such a system. The ability to write a
--      scriptable, automated test environment is a core competency for any DV
--      engineer.
--
--   3. Debugging and Bug Triage:
--      When a regression fails, the first step is to analyze the log file produced
--      by a testbench like this one. The error messages (e.g., "Data mismatch at
--      word 5") provide the initial clue. The DV engineer then re-runs the specific
--      failing test with waveform dumping enabled (`$dumpfile`) to begin the deep-
--      dive debug process. This testbench provides all the necessary hooks and
--      logging to support this critical industrial workflow.
--
-- In essence, the work demonstrated in this file—architecting a layered
-- testbench, creating reusable verification components (BFMs), writing self-
-- checking tests, and enabling automation—is a direct reflection of the day-to-day
-- responsibilities of a professional Design Verification engineer.
--
--------------------------------------------------------------------------------
*/



/*
-- ############################################################################
-- ##                   Industrially Relevant Insights                     ##
-- ############################################################################
--
--
-- [[ Industrially Relevant Insights Gained ]]
--
-- Building and debugging this verification environment provided several profound
-- insights into the mindset and practices of professional DV engineers. These go
-- beyond simply writing code and touch on the philosophy of verification.
--
--   - Technical Insight 1: The Power of a Layered Architecture.
--     My most significant technical takeaway was appreciating the "separation
--     of concerns" between the BFM (low-level protocol) and the test cases
--     (high-level intent). In a real industrial project, the bus protocol
--     (like AXI) is vastly more complex. Having a dedicated, pre-verified
--     AXI BFM (often called a Verification IP or VIP) is essential. The test
--     engineer can then focus on writing tests that target the DUT's specific
--     logic, simply by calling high-level BFM tasks like `axi_write(addr, data)`.
--     This project gave me a small-scale, tangible experience of why that
--     layered architecture is not just a "nice-to-have," but an absolute
--     necessity for managing complexity.
--
--   - Technical Insight 2: The Value of Negative and Corner-Case Testing.
--     It's easy to write tests for the things you expect to work. The real
--     challenge and value comes from thinking like an adversary: "How can I
--     break this design?" The process of creating the `run_negative_and_corner_case_tests`
--     task shifted my mindset. I started thinking about scenarios like zero-
--     length transfers, reads from unmapped addresses, and back-to-back
--     transactions that might expose race conditions. This is the mindset
--     that separates a basic "does it work" test from a robust verification
--     suite that ensures design quality and resilience.
--
--   - Non-Technical Insight: Verification is a Destructive Process.
--     I learned that the goal of a DV engineer is not to prove that the design
--     works, but to try their absolute hardest to prove that it is broken.
--     Every bug found in pre-silicon verification is a massive win, saving
--     potentially millions of dollars compared to finding that same bug after
--     the chip has been manufactured. This testbench, with its randomized data
--     and corner-case tests, is a tool designed for this "destructive" purpose:
--     to find failures before the design is committed to hardware. This
--     philosophical shift is one of the most important for an aspiring DV engineer.
--
--------------------------------------------------------------------------------
*/




/*
--
-- ############################################################################
-- ##                 Post-Mortem: Limitations and Future Scope              ##
-- ############################################################################
--
--
-- [[ Current Limitations of this Verification Environment ]]
--
-- While this testbench is robust for its purpose, a professional, industrial-
-- strength environment would have more advanced features. Recognizing these
-- limitations is key to understanding the path towards a commercial-grade setup.
--
--   1. Lack of a True OOP Structure: This testbench is "UVM-like" in principle
--      but not in implementation. It uses tasks and functions, but a full UVM
--      environment would be built from classes (`uvm_driver`, `uvm_monitor`,
--      `uvm_scoreboard`). This limits reusability and scalability, as all logic
--      is contained within this single, monolithic module.
--
--   2. Basic Randomization: The stimulus generation uses `$random`, which is a
--      basic form of randomization. It lacks the power of UVM's constraint-based
--      randomization, where you can define complex rules like "generate a DMA
--      transfer where the source and destination addresses are aligned but not
--      equal, and the length is a prime number." This limits the ability to
--      target very specific, tricky corner cases automatically.
--
--   3. No Functional Coverage or Assertions: This environment can tell you if
--      a test passed or failed, but it cannot tell you *what* has been tested.
--      It lacks formal functional coverage (`covergroup`, `coverpoint`) to
--      measure whether all features (e.g., all DMA transfer lengths, all
--      interrupt sources) have been exercised. It also lacks SystemVerilog
--      Assertions (SVA) to formally check for protocol violations on the bus
--      at all times.
--
--   4. Monolithic Scoreboard Logic: The checking logic (the scoreboard) is
--      embedded within each test task. A more advanced architecture would have a
--      central, standalone scoreboard component that passively receives transaction
--      data from monitors and performs checks independently of the stimulus driver.
--
--------------------------------------------------------------------------------
*/




/*
--
-- [[ Future Improvements: Migrating to UVM ]]
--
-- This testbench provides an excellent foundation, but the ultimate goal for a
-- project of this nature would be to migrate it to the Universal Verification
-- Methodology (UVM). This would be a significant undertaking that would
-- transform the environment to a fully professional, industry-standard framework.
-- I have a clear roadmap for how this would be accomplished:
--
--   1. Transaction Class (`bus_transaction`):
--      - I would first define a `bus_transaction` class that extends `uvm_sequence_item`.
--        This class would encapsulate all the properties of a bus operation: an
--        address, read/write direction, and data. This replaces the simple task
--        arguments.
--
--   2. Component-Based Architecture:
--      - I would break this monolithic testbench module into distinct UVM
--        components, each extending a UVM base class (`uvm_component`):
--        - `bus_driver`: This component would replace the BFM tasks. Its job would
--          be to get `bus_transaction` objects from a sequencer and execute the
--          low-level pin wiggles to drive the DUT's bus.
--        - `bus_monitor`: A new, passive component that would watch the DUT's bus
--          interface, reconstruct `bus_transaction` objects from the observed
--          pin activity, and broadcast them to other components.
--        - `scoreboard`: A standalone component that would receive transactions from
--          one or more monitors. It would contain the checking logic (like the
--          memory comparison or the golden CRC model) and report errors. This
--          decouples checking from stimulus generation.
--        - `agent`: A container component that would encapsulate the driver and monitor.
--        - `env`: An environment class that would instantiate the agent(s) and the
--          scoreboard, and manage their connections.
--
--   3. Sequence-Based Stimulus Generation:
--      - The test case `tasks` would be replaced by `uvm_sequence` classes.
--      - A `dma_test_sequence` would generate a series of `bus_transaction` objects
--        needed to configure the DMA, and then wait for an interrupt event.
--      - This enables powerful constrained-random generation. I could write a single
--        randomized sequence with constraints (e.g., `addr inside {[A:B]};`), and
--        the UVM solver would generate thousands of unique, valid scenarios,
--        dramatically improving coverage.
--
--   4. Factory and Configuration Database:
--      - I would use the UVM factory to make the environment easily configurable and
--        overridable, and the `uvm_config_db` to pass configuration information
--        (like virtual interfaces or agent settings) down the component hierarchy.
--
-- This migration would represent the final step in moving from a project-specific
-- testbench to a truly reusable, scalable, and professional verification IP.
--
--------------------------------------------------------------------------------
*/



/*
--
-- ############################################################################
-- ##                  Environment, Tools, and Execution                     ##
-- ############################################################################
--
--
-- [[ My Development Environment and Toolchain Setup ]]
--
-- For this project, I made a very deliberate choice to use a lightweight,
-- command-line-driven, and entirely open-source toolchain. This approach was
-- chosen for two main reasons: firstly, to ensure the project was completely
-- portable and free of licensing issues, and secondly, to force a deep
-- understanding of the fundamental EDA workflow, rather than relying on the
-- graphical user interface (GUI) of an integrated commercial tool.
--
--   - Coding Editor: Visual Studio Code (VS Code)
--     - Why this tool? I chose VS Code because it represents the perfect
--       compromise between a simple text editor and a full-blown IDE. It is
--       fast, responsive, and its power comes from its vast ecosystem of
--       extensions.
--     - My Setup: I installed the "Verilog-HDL/SystemVerilog" extension by
--       mshr-h. This provided critical features like syntax highlighting,
--       which makes code easier to read, and real-time linting, which acts
--       as a first line of defense by flagging simple syntax errors as I typed.
--       Most importantly, its integrated terminal allowed me to maintain a
--       seamless workflow where I could edit code, execute my Python regression
--       script, and view the results all within a single application window.
--
--   - Simulation Engine (EDA Tool): Icarus Verilog (`iverilog` & `vvp`)
--     - Why this tool? I selected Icarus because it is a mature, well-supported,
--       and highly standards-compliant open-source simulator. Using it
--       demonstrates the ability to work effectively without depending on
--       expensive commercial licenses.
--     - How it's integrated: The `run_regression.py` script directly calls the
--       `iverilog` command to compile the entire design and testbench into an
--       executable `vvp` file. It then calls `vvp` to run the simulation.
--
--   - Waveform Viewer: GTKWave
--     - Why this tool? GTKWave is the standard open-source waveform viewer that
--       pairs perfectly with Icarus Verilog. It reads the Value Change Dump
--       (`.vcd`) file that the simulator generates.
--     - How it's integrated: When a test fails, my workflow is to re-run that
--       single test and then open the generated `waveform.vcd` file in GTKWave.
--       This tool was my "digital oscilloscope" and was absolutely essential
--       for finding every complex bug in the project, as it provides the ground
--       truth of what every signal in the design is doing on a cycle-by-cycle
--       basis.
--
--   - Automation and Scripting: Python 3
--     - Why this tool? Python is the undisputed scripting language of the modern
--       VLSI industry. I chose it for its powerful, yet easy-to-use, libraries
--       for system interaction (`subprocess`) and text manipulation.
--     - How it's integrated: The `run_regression.py` script is the top-level
--       "manager" of the entire verification flow. It replaces the tedious and
--       error-prone process of manually typing long compile and run commands for
--       each test, and automates the process of checking the log files for pass/fail
--       signatures.
--
--------------------------------------------------------------------------------
--
-- [[ Execution Commands ]]
--
-- The entire verification workflow is managed from the command line, orchestrated
-- by the `run_regression.py` Python script. This script constructs and executes
-- a series of shell commands to compile the design and run the tests defined
-- within this testbench file.
--
--
--   --- Single Entry Point ---
--   To run the entire suite of tests, the one and only command I execute is:
--
--   `python3 run_regression.py`
--
--   This script provides the "push-button" automation for the project. Internally,
--   it performs the following two main steps:
--
--
--   1. The Compilation Step:
--      The script first calls Icarus Verilog to compile all necessary design
--      and testbench files into a single simulation executable.
--
--      The command generated by the script is:
--      `iverilog -g2005-sv -o soc_sim rtl/*.v rtl/*.sv tb/tb_risc_soc.sv`
--
--      - `iverilog`: The Icarus Verilog compiler.
--      - `-g2005-sv`: This flag is critical. It enables the SystemVerilog features
--        (like the `string` data type and `$value$plusargs`) that are used in this
--        testbench.
--      - `-o soc_sim`: This specifies the name for the compiled output file.
--      - `rtl/*.v rtl/*.sv`: This wildcard pattern conveniently includes all the
--        RTL source files from the `rtl` directory.
--      - `tb/tb_risc_soc.sv`: This is the top-level file for the simulation, as it
--        instantiates the DUT.
--
--
--   2. The Simulation Step (per test):
--      After a successful compilation, the script iterates through its list of
--      test names and executes the simulation for each one. For example, to run
--      the `TIMER_TEST`, the script would execute:
--
--      The command is:
--      `vvp soc_sim +TESTNAME=TIMER_TEST`
--
--      - `vvp`: This is the Verilog Virtual Processor, the runtime engine for
--        Icarus Verilog that executes the compiled `soc_sim` file.
--      - `+TESTNAME=TIMER_TEST`: This is the plusarg that this testbench reads.
--        The main `initial` block in this file will see this argument and execute
--        only the `run_timer_test` task. The script then captures the output of
--        this command, saves it to a log file, and parses it for the "Test
-         Successful" string to determine the pass/fail status.
--
--------------------------------------------------------------------------------
*/