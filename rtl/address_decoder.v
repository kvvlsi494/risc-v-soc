// Copyright (c) 2025 Kumar Vedang
// SPDX-License-Identifier: MIT
//
// This source file is part of the RISC-V SoC project.
//


/*
--------------------------------------------------------------------------------
-- Module Name: address_decoder
-- Project: Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: Kumar Vedang
--------------------------------------------------------------------------------
--
-- Description:
--
-- This module, `address_decoder`, serves as the central "switchboard" or "post 
-- office" for the entire System-on-Chip. Its fundamental responsibility is to 
-- implement the system's memory map. It constantly monitors the main system 
-- bus address, which is driven by the currently active bus master (either the 
-- CPU or the DMA engine), and determines which slave peripheral is being 
-- targeted by the current bus transaction.
--
-- How it works:
-- The decoder examines the most significant bits of the 32-bit address bus. 
-- Based on a predefined address map, it generates a unique, active-low chip-select 
-- signal (_cs_n) for one, and only one, of the slave peripherals (e.g., on-chip 
-- RAM, DMA controller's configuration port, CRC accelerator, etc.). This chip-select 
-- signal effectively "wakes up" the targeted slave, informing it that it should 
-- respond to the current read or write request on the bus.
--
-- Integration and Communication:
-- - Receives input from: The main system bus `addr` line. This `addr` line itself 
--   is the output of a multiplexer that selects between the CPU's address bus 
--   and the DMA's address bus, based on the arbiter's grant signal.
-- - Sends output to: All slave peripherals in the SoC. Each slave (RAM, DMA, CRC, 
--   Timer, UART, Interrupt Controller) has a `cs_n` input port that is directly 
--   connected to one of the output ports of this decoder.
--
-- Significance in the Project:
-- The `address_decoder` is the physical hardware implementation of the architectural
-- concept of Memory-Mapped I/O (MMIO). Without this block, the masters (CPU/DMA)
-- would have no mechanism to direct their requests to specific slaves, and the 
-- entire system would be unable to communicate. Its logic is simple, but its 
-- role is absolutely critical for the SoC's operation. It forms the core of the
-- system's interconnect logic.
--
--------------------------------------------------------------------------------
*/


/*
--------------------------------------------------------------------------------
-- Development Environment and Toolchain
--------------------------------------------------------------------------------
--
-- - Language: Verilog (IEEE 1364-2001) for portable, synthesizable RTL.
-- - Editor: Visual Studio Code w/ Verilog-HDL extension for syntax highlighting.
-- - Simulator: Icarus Verilog (iverilog), an open-source EDA tool.
-- - Debugging: GTKWave for visual waveform analysis of .vcd files.
-- - Automation: Python for the regression script (`run_regression.py`).
--
--------------------------------------------------------------------------------
*/


`timescale 1ns / 1ps



module address_decoder (

    input [31:0] addr,
    output ram_cs_n,
    output dma_cs_n,
    output crc_cs_n,
    output intc_cs_n,
    output timer_cs_n,
    output uart_cs_n // Unified UART CS
);

    // This section contains the core logic of the decoder. It uses 'assign' statements,
    // which create continuous assignments in Verilog. This means the output on the left-hand
    // side will instantly and combinationally change whenever any signal on the right-hand side changes.
    // This synthesizes directly to pure combinational logic gates (comparators and multiplexers) 
    // with no clock or memory elements.

    // Line 1: RAM Chip Select Logic
    //This assigns a 64KB block to the RAM.
    assign ram_cs_n = (addr[31:16] == 16'h0000) ? 1'b0 : 1'b1;


    // Line 2: DMA Chip Select Logic
    assign dma_cs_n = (addr[31:16] == 16'h0001) ? 1'b0 : 1'b1;


    // Line 3: CRC Accelerator Chip Select Logic
    assign crc_cs_n = (addr[31:16] == 16'h0002) ? 1'b0 : 1'b1;


    // Line 4: Interrupt Controller Chip Select Logic
    assign intc_cs_n = (addr[31:16] == 16'h0003) ? 1'b0 : 1'b1;


    // Line 5: Timer Chip Select Logic
    assign timer_cs_n = (addr[31:16] == 16'h0004) ? 1'b0 : 1'b1;



    // Line 6: UART Chip Select Logic
    assign uart_cs_n = (addr[31:16] == 16'h0005) ? 1'b0 : 1'b1; // UART at 0x0005_xxxx

endmodule



