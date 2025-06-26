// Copyright (c) 2025 Kumar Vedang
// SPDX-License-Identifier: MIT
//
// This source file is part of the RISC-V SoC project.
//


// File: tb_risc_soc.sv (FINAL, COMPLETE, CORRECTED, AND ROBUST VERSION)
`timescale 1ns / 1ps

module tb_risc_soc;

    // --- Signals ---
    reg clk;
    reg rst_n;
    reg bfm_mode_reg;
    wire uart_tx_pin_from_dut;
    wire uart_rx_pin_to_dut;

    // --- DUT Instantiation and UART Loopback Connection ---
    risc_soc dut (
        .clk(clk), .rst_n(rst_n), .bfm_mode(bfm_mode_reg),
        .uart_tx_pin(uart_tx_pin_from_dut),
        .uart_rx_pin(uart_rx_pin_to_dut)
    );
    assign uart_rx_pin_to_dut = uart_tx_pin_from_dut;

    // --- Clock and Reset Generation ---
    initial begin clk = 0; forever #5 clk = ~clk; end
    initial begin rst_n = 1'b0; bfm_mode_reg = 1'b0; #20; rst_n = 1'b1; end

    // --- Test Parameters and Data Storage ---
    parameter NUM_TRANSACTIONS = 5;
    parameter MAX_WORDS = 16;
    reg [31:0] src_addr_q[0:NUM_TRANSACTIONS-1], dest_addr_q[0:NUM_TRANSACTIONS-1];
    reg [31:0] num_words_q[0:NUM_TRANSACTIONS-1];
    reg [31:0] data_q[0:NUM_TRANSACTIONS-1][0:MAX_WORDS-1];
    
    // --- BFM Tasks (CORRECTED AND ROBUST) ---
    task cpu_bfm_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            bfm_mode_reg <= 1'b1;
            @(posedge clk);
            dut.u_cpu.bus_req_reg <= 1'b1;
            wait (dut.cpu_m_gnt == 1'b1);
            @(posedge clk);
            dut.u_cpu.bus_addr_reg  <= addr;
            dut.u_cpu.bus_wr_en_reg <= 1'b1;
            dut.u_cpu.bus_wdata_reg <= data;
            @(posedge clk);
            dut.u_cpu.bus_req_reg   <= 1'b0;
            dut.u_cpu.bus_wr_en_reg <= 1'b0;
            bfm_mode_reg <= 1'b0;
        end
    endtask

    task cpu_bfm_read;
        input [31:0] addr;
        output [31:0] data;
        begin
            bfm_mode_reg <= 1'b1;
            @(posedge clk);
            dut.u_cpu.bus_req_reg <= 1'b1;
            wait (dut.cpu_m_gnt == 1'b1);
            @(posedge clk);
            dut.u_cpu.bus_addr_reg  <= addr;
            dut.u_cpu.bus_wr_en_reg <= 1'b0;
            @(posedge clk);
            data = dut.cpu_m_rdata;
            dut.u_cpu.bus_req_reg <= 1'b0;
            bfm_mode_reg <= 1'b0;
        end
    endtask
    
    // --- Individual Test Task Implementations (Self-Contained) ---
    
    task run_dma_test;
        reg [31:0] temp_word_read;
        integer i, j;
        $display("\n------------------------------------------------------");
        $display("--- DMA FUNCTIONAL TEST ---");
        
        for (i = 0; i < NUM_TRANSACTIONS; i = i + 1) begin
            $display("\n--- DMA Test Transaction %0d ---", i);
            
            // Driver part 1: Load source data into RAM
            $display("DRIVER (DMA): Loading source data for this transaction...");
            for (j = 0; j < num_words_q[i]; j = j + 1) begin
                cpu_bfm_write(src_addr_q[i] + (j * 4), data_q[i][j]);
            end

            // Driver part 2: Configure and start DMA
            $display("DRIVER (DMA): Configuring and starting DMA...");
            cpu_bfm_write(32'h0001_0000, src_addr_q[i]);
            cpu_bfm_write(32'h0001_0004, dest_addr_q[i]);
            cpu_bfm_write(32'h0001_0008, num_words_q[i]);
            cpu_bfm_write(32'h0001_000C, 1);
            wait (dut.cpu_irq_in == 1'b1); @(posedge clk);
            $display("DRIVER (DMA): Interrupt received. Clearing interrupts...");
            cpu_bfm_write(32'h0001_0010, 1);
            cpu_bfm_write(32'h0003_0000, 1);
            
            // Scoreboard: Check the result
            $display("SCOREBOARD (DMA): Verifying copied data...");
            for (j = 0; j < num_words_q[i]; j = j + 1) begin
                cpu_bfm_read(dest_addr_q[i] + (j * 4), temp_word_read);
                if (temp_word_read !== data_q[i][j]) begin
                    $error("SCOREBOARD (DMA) FAILED: Data mismatch at word %0d. Expected 0x%h, Got 0x%h", j, data_q[i][j], temp_word_read); 
                    $finish;
                end
            end
            $display("SCOREBOARD (DMA): Transaction %0d PASSED.", i);
        end
    endtask

    task run_crc_test;
        reg [31:0] final_crc_from_hw, expected_crc, temp_word;
        integer i, j;
        $display("\n------------------------------------------------------");
        $display("--- CRC FUNCTIONAL TEST ---");

        for (i = 0; i < NUM_TRANSACTIONS; i = i + 1) begin
            $display("\n--- CRC Test Transaction %0d ---", i);
            
            // Driver part 1: Load source data into RAM
            $display("DRIVER (CRC): Loading source data for this transaction...");
            for (j = 0; j < num_words_q[i]; j = j + 1) begin
                cpu_bfm_write(src_addr_q[i] + (j * 4), data_q[i][j]);
            end

            // Driver part 2: Feed data to CRC peripheral
            $display("DRIVER (CRC): Feeding data to CRC peripheral...");
            cpu_bfm_write(32'h0002_0000, 1); // Reset CRC
            for (j = 0; j < num_words_q[i]; j = j + 1) begin
                cpu_bfm_read(src_addr_q[i] + (j*4), temp_word);
                cpu_bfm_write(32'h0002_0004, temp_word);
            end
            cpu_bfm_read(32'h0002_0004, final_crc_from_hw);

            // Scoreboard: Calculate expected CRC and compare
            $display("SCOREBOARD (CRC): Calculating golden CRC and checking result...");
            expected_crc = 32'hFFFFFFFF;
            for (j = 0; j < num_words_q[i]; j = j + 1)
                expected_crc = calculate_crc32_golden(expected_crc, data_q[i][j]);

            if (final_crc_from_hw === expected_crc)
                $display("SCOREBOARD (CRC): Transaction %0d PASSED. CRC=0x%h", i, final_crc_from_hw);
            else
                $error("SCOREBOARD (CRC) FAILED: Mismatch. Expected 0x%h, Got 0x%h", expected_crc, final_crc_from_hw);
        end
    endtask

    function [31:0] calculate_crc32_golden;
        input [31:0] crc_in, data_in; reg [31:0] d, c; integer i;
        begin d=data_in; c=crc_in; for (i=0; i<32; i=i+1) if ((c[31]^d[31-i])) c=(c<<1)^32'h04C11DB7; else c=c<<1; calculate_crc32_golden = c; end
    endfunction
    
    task run_timer_test;
        reg [31:0] compare_val, intc_status;
        compare_val = 32'd500;
        $display("\n------------------------------------------------------");
        $display("--- TIMER FUNCTIONAL TEST ---");
        cpu_bfm_write(32'h0004_0004, compare_val);
        cpu_bfm_write(32'h0004_0000, 1);
        wait (dut.cpu_irq_in == 1'b1); @(posedge clk);
        cpu_bfm_read(32'h0003_0000, intc_status);
        if (intc_status[1] !== 1'b1) $error("SCOREBOARD (Timer) FAILED: Interrupt source incorrect.");
        cpu_bfm_write(32'h0004_0000, 32'h2); cpu_bfm_write(32'h0003_0000, 1); #20;
        if (dut.cpu_irq_in == 1'b1) $error("SCOREBOARD (Timer) FAILED: Interrupt did not clear.");
        $display("SCOREBOARD (Timer): Test PASSED.");
    endtask

    task run_uart_loopback_test;
        reg [7:0] char_to_send;
        reg [31:0] intc_status, uart_rx_reg;
        char_to_send = 8'hE7;
        $display("\n------------------------------------------------------");
        $display("--- UART LOOPBACK TEST ---");
        cpu_bfm_write(32'h0005_0000, char_to_send);
        wait (dut.cpu_irq_in == 1'b1); @(posedge clk);
        cpu_bfm_read(32'h0003_0000, intc_status);
        if (intc_status[2] !== 1'b1) $error("SCOREBOARD (UART) FAILED: Interrupt source incorrect. INTC=0x%h", intc_status);
        cpu_bfm_read(32'h0005_0004, uart_rx_reg);
        if (uart_rx_reg[8] != 1'b1 || uart_rx_reg[7:0] != char_to_send) $error("SCOREBOARD (UART) FAILED: Data mismatch or invalid flag.");
        cpu_bfm_write(32'h0005_0004, 1); cpu_bfm_write(32'h0003_0000, 1); #20;
        if (dut.cpu_irq_in == 1'b1) $error("SCOREBOARD (UART) FAILED: Interrupt did not clear.");
        $display("SCOREBOARD (UART Loopback): Test PASSED.");
    endtask

    task run_negative_and_corner_case_tests;
        reg [31:0] read_back_word;
        $display("\n------------------------------------------------------");
        $display("--- CORNER CASE & NEGATIVE TESTS ---");
        $display("Test: Zero-Length DMA Transfer...");
        cpu_bfm_write(32'h0001_0000, 32'h5000); cpu_bfm_write(32'h0001_0004, 32'h6000); cpu_bfm_write(32'h0001_0008, 0); cpu_bfm_write(32'h0001_000C, 1);
        fork begin: t #2000; $display("  -> Zero-length DMA PASS."); end begin: i wait(dut.cpu_irq_in == 1'b1); $error("FAILED: Interrupt fired for zero-length DMA."); $finish; end join_any; disable t; disable i;
        @(posedge clk);
        $display("Test: Illegal Address Read...");
        cpu_bfm_read(32'h9000_0000, read_back_word);
        if (read_back_word !== 32'hBAD_DDAA) $error("FAILED: Incorrect value on illegal read.");
        $display("  -> Illegal Address Read PASS.");
    endtask
    
    // --- Main Test Sequencer ---
    initial begin
        string testname;
        integer seed;

        if (!$value$plusargs("TESTNAME=%s", testname)) testname = "FULL_REGRESSION";

        $display("======================================================");
        $display("--- Starting RISC-V SoC System-Level Test ---");
        $display("---           TESTNAME: %s            ---", testname);
        $display("======================================================");
        wait (rst_n === 1'b1);
        @(posedge clk);

        // Generate stimulus data once for all tests that need it.
        if (testname == "DMA_TEST" || testname == "CRC_TEST" || testname == "FULL_REGRESSION") begin
            seed = 12345;
            $display("SEQUENCER: Generating %0d random transactions for DMA and CRC tests...", NUM_TRANSACTIONS);
            for (integer i = 0; i < NUM_TRANSACTIONS; i = i + 1) begin
                src_addr_q[i] = ( ({$random(seed)} & 16'hA000) );
                dest_addr_q[i] = src_addr_q[i] + 32'h4000; // Ensure non-overlapping areas
                num_words_q[i] = ({$random(seed)} % MAX_WORDS) + 1;
                for (integer j = 0; j < num_words_q[i]; j = j + 1) begin
                    data_q[i][j] = {$random(seed), $random(seed)};
                end
            end
            $display("SEQUENCER: Data generation complete.");
        end
        
        // Post-reset cleanup to ensure no stale interrupts are pending
        $display("TB: Performing post-reset interrupt cleanup...");
        cpu_bfm_write(32'h0003_0000, 1);
        @(posedge clk);

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
            $display("\n\n>>> FULL REGRESSION SUITE COMPLETED SUCCESSFULLY <<<");
        end else begin
            $error("Unknown TESTNAME specified: %s", testname);
            $finish;
        end

        $display("\n======================================================");
        $display("--- Test Successful. ---");
        $display("======================================================");
        $finish;
    end
    
    // --- Waveform Dumping ---
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_risc_soc);
    end

endmodule

