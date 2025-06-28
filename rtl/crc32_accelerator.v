// Copyright (c) 2025 Kumar Vedang
// SPDX-License-Identifier: MIT
//
// This source file is part of the RISC-V SoC project.
//


/*
--------------------------------------------------------------------------------
-- Module Name: crc32_accelerator
-- Project: A Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: Kumar Vedang
--------------------------------------------------------------------------------
--
-- High-Level Module Purpose:
-- This module, `crc32_accelerator`, is a piece of dedicated hardware IP
-- (Intellectual Property) designed to perform one task exceptionally well:
-- calculating a 32-bit Cyclic Redundancy Check (CRC-32) value for a stream of
-- data, following the standard Ethernet polynomial.
--
-- Significance in the SoC Architecture:
-- The primary significance of this block is to serve as a tangible example of
-- the "hardware offload" or "hardware acceleration" design pattern, which is
-- a fundamental concept in modern VLSI. Instead of forcing the main CPU to
-- execute hundreds of software instructions to compute a CRC, we offload this
-- repetitive and computationally intensive task to this specialized, and
-- therefore much faster and more power-efficient, hardware block. This frees
-- up the CPU to handle more complex control-flow tasks.
--
-- Communication and Integration:
-- This module operates purely as a slave peripheral on the system's shared bus.
-- It never initiates a bus transaction itself. Its behavior is dictated by the
-- active bus master (either the CPU or the DMA).
--
--   - Receiving Commands: It is connected to the main system bus. When a master
--     places an address on the bus that falls within this module's assigned
--     range, the top-level `address_decoder` will assert this module's `cs_n`
--     (chip select) line. The module then uses the `wr_en` and `addr` signals
--     to perform a write to one of its internal registers.
--
--   - Sending Data: During a read operation (`wr_en` is low), this module
--     drives its calculated result onto the shared `rdata` bus, which is then
--     routed back to the requesting master by the top-level multiplexer.
--
-- This module is a key component in two of the main verification scenarios:
--   1. The `CRC_TEST`, where the CPU directly controls it.
--   2. (Implicitly) A more advanced test where the DMA could be programmed to
--      stream data from RAM directly into this accelerator.
--
--------------------------------------------------------------------------------
*/

`timescale 1ns / 1ps


//The port list in the parentheses defines its complete input/output interface.
module crc32_accelerator (

    // --- System Signals ---
    // It is driven by the main clock source in the testbench.
    input clk,

    // When this signal is driven to '0', the module must immediately (without
    // waiting for a clock edge) return to its defined initial state. This is
    // critical for system power-on and recovery.
    input rst_n,
    
    
    // --- Simple Slave Bus Interface ---
    // This is a standard set of signals for a memory-mapped slave peripheral.
    input cs_n,


    // `wr_en`: A single-bit input for the write enable signal. This is driven by
    // the active bus master and dictates the direction of the transaction.
    // A '1' indicates a write cycle, and a '0' indicates a read cycle.
    input wr_en,

    // `addr`: A 2-bit input address bus. The top-level `address_decoder` maps
    // a large block of memory space to this peripheral. These lower address bits
    // are used to select specific registers *within* this module, allowing for
    // more granular control. A 2-bit address provides access to 4 unique
    // 32-bit (word-aligned) register locations (at offsets 0x0, 0x4, 0x8, 0xC).
    input [1:0] addr,


    // `wdata`: A 32-bit input data bus. During a write cycle, this bus carries
    // the data from the master that is intended to be written into the selected
    // internal register of this module.
    input [31:0] wdata,


    // `rdata`: A 32-bit output data bus. During a read cycle, the module places
    // the contents of its selected internal register onto this bus. This signal
    // is connected to a wide multiplexer at the top level, which routes the
    // data back to the requesting master.
    output [31:0] rdata

);

// --- Internal State Declaration ---

// It is declared as a `reg` in Verilog, which is a variable type capable of
// storing a value.
reg [31:0] crc_reg;



// --- Constant Declaration ---

// Purpose: This specific value, 32'hFFFFFFFF, is the standard initial value
// required by most CRC-32 algorithms before any data is processed, ensuring
// compliance with the specification.
parameter CRC_INITIAL_VALUE = 32'hFFFFFFFF;



// --- Combinational Read Logic and Bus Protocol Compliance ---

// The condition `(!cs_n && !wr_en)` checks for two things simultaneously:
//   1. `!cs_n`: Is the chip select active (low)? This means the address decoder
//      has selected THIS peripheral.
//   2. `!wr_en`: Is this NOT a write operation? This means it must be a read.
//
// If both conditions are true (it is a read cycle targeting this peripheral):
//   - The `rdata` output is driven with the current value of the internal `crc_reg`.
//
// If the condition is false (it's a write, or another peripheral is selected):
//   - The `rdata` output is driven with `32'hZZZZZZZZ`. This is a 32-bit high-
//     impedance value. In hardware synthesis, this creates a tri-state buffer
//     on the output. Driving 'Z' effectively "disconnects" this module's output
//     from the bus, allowing another selected slave to drive the `rdata` bus
//     without contention.
//
// The Bug this Prevents:
// If this line was simply `assign rdata = crc_reg;`, this module would be
// *continuously* trying to drive the `rdata` bus. When another peripheral
// (like the On-Chip RAM) was selected for a read, both would drive the bus at
// the same time, causing a "bus fight" and resulting in an unknown ('X') value
// being read by the master. This logic prevents that critical failure.
assign rdata = (!cs_n && !wr_en) ? crc_reg : 32'hZZZZZZZZ;



// --- Sequential Write Logic ---
// This `always` block describes all the logic that has memory or state, meaning
// its outputs depend on previous inputs. In hardware, this block will be
// synthesized into flip-flops and the logic that feeds them.
always @(posedge clk or negedge rst_n) begin

    // --- Asynchronous Reset Implementation ---
    if (!rst_n) begin

        // The non-blocking assignment (`<=`) is used for sequential logic. It
        // models the behavior of a flip-flop, where the output is updated based
        // on the input at the clock edge.
        crc_reg <= CRC_INITIAL_VALUE;
    end 
    
     // --- Synchronous Operation Logic ---
    else begin

        // --- Write Cycle Detection ---
        // This condition checks if a valid write cycle is targeting this specific
        // peripheral.
        if (!cs_n && wr_en) begin

            // --- Internal Register Map Decoding ---
            // A `case` statement is a clear way to implement a decoder.
            case (addr)

                // This branch executes if `addr` is 2'b00 (offset 0x0).
                // This corresponds to the module's "Control Register."
                2'b00: begin

                // A write to this address performs a software-triggered reset of
                // the CRC calculation, re-loading the initial value.
                crc_reg <= CRC_INITIAL_VALUE;
                end


                // This branch executes if `addr` is 2'b01 (offset 0x4).
                // This corresponds to the module's "Data Register."
                2'b01: begin

                    // The `crc_reg` is updated with the result of the `calculate_crc32`
                    // function.
                    crc_reg <= calculate_crc32(crc_reg, wdata);
                end

                // --- Default Case for Safety ---
                // The `default` case is a good design practice. It catches any
                // accesses to unused addresses within the module's allocated space
                // (e.g., 2'b10 or 2'b11).
                default: begin

                    // By assigning the register to itself, we ensure that writes
                    // to unsupported addresses have no effect on the module's state.
                    crc_reg <= crc_reg;
                end
            endcase
        end
    end
end

// --- Purely Combinational Calculation Function ---
// In Verilog, a `function` is used to define a piece of reusable, purely
// combinational logic. It cannot contain timing controls (like `@(posedge clk)`)
// and must execute in zero simulation time. The result is returned through a variable
// with the same name as the function.
function [31:0] calculate_crc32;

    // --- Function Arguments ---
    // The `input` declarations define the arguments the function takes.
    input [31:0] crc_in;
    input [31:0] data_in;

    // --- Internal Function Variables ---
    // These are temporary variables used only within the scope of the function.
    reg [31:0] d;
    reg [31:0] c;
    integer i; // Used as the loop counter.

    // The `begin...end` block contains the executable algorithm.
    begin

        // The local variables are initialized with the function's input values.
        d = data_in;
        c = crc_in;

        // This `for` loop implements the core of the bit-serial CRC algorithm.
        // It iterates 32 times
        for (i = 0; i < 32; i = i + 1) begin

            // It XORs the most significant bit of the current CRC (`c[31]`) with the current
            // data bit (`d[31-i]`).
            if ((c[31] ^ d[31-i]) == 1'b1) begin

                // If the result of the XOR is 1, the CRC register is first shifted
                // left by 1 bit, and the result is then XORed with the standard
                // Ethernet CRC-32 polynomial (0x04C11DB7).
                c = (c << 1) ^ 32'h04C11DB7;

            // The `else` part of the conditional logic.
            end else begin

                // If the result of the XOR is 0, the CRC register is simply
                // shifted left by 1 bit, with no polynomial XOR.
                c = c << 1;
            end
        end

        // After 32 iterations, the final value of `c` is assigned to the function's
        // return variable, which has the same name as the function itself.
        calculate_crc32 = c;
    end
endfunction

endmodule

/*
--
-- Industrially Relevant Insights Gained
--
-- Building this module provided several key insights that are directly
-- applicable to a professional VLSI role:
--
--   - Technical Insight: The absolute necessity of robust bus interface logic.
--     My key takeaway was that an IP block's internal logic is useless if its
--     interface to the system bus is flawed. Implementing the tri-state output
--     on `rdata` correctly was not just a feature; it was a prerequisite for
--     the entire system to function. In industry, this translates to rigorously
--     adhering to standard bus protocols like AXI, APB, or AHB. You don't get
--     to invent the protocol; you must follow it perfectly.
--
--   - Design-for-Verification Insight: While designing the module, I had to
--     think about how I would test it. This led me to add a specific "software
--     reset" feature by making a write to address 0x0 reset the `crc_reg`.
--     This feature isn't strictly necessary for the CRC calculation itself, but
--     it makes the block far more controllable and easier to test in a
--     regression environment, as the testbench can deterministically reset the
--     state without using the global hardware reset pin. This is a simple
--     example of "Design for Verification" (DFV).
--
--   - Non-Technical Insight: The value of modularity and reuse. By building
--     this as a self-contained module with a standard interface, it becomes a
--     reusable piece of IP. In a company, this block could be taken and dropped
--     into dozens of different chip designs with minimal modification. This
--     project made me appreciate that the real value is not just in designing a
--     block, but in designing a *reusable and verifiable* block.
--
--------------------------------------------------------------------------------
*/




/*
-- ############################################################################
-- ##                Post-Mortem: Bugs, Limitations, and Future              ##
-- ############################################################################
--
--
-- [[ Most Challenging Bug and Debugging Process ]]
--
-- Bug Symptom: During the initial system-level integration, the `CRC_TEST` was
-- failing intermittently. The testbench scoreboard reported that the final CRC
-- value read from the hardware was `32'hXXXXXXXX` (an unknown value, or 'X'),
-- even though the unit test for this module had passed perfectly.
--
-- My Debugging Process:
--
--   1. Hypothesis: My first thought was that the `crc_reg` itself was becoming
--      corrupted. However, since the unit test passed, I suspected the issue
--      was related to system integration. The 'X' value strongly suggested a
--      bus-level problem. My hypothesis became: "Two or more slave peripherals
--      are trying to drive the `rdata` bus at the same time."
--
--   2. Evidence Gathering (Waveform Analysis): I opened the GTKWave viewer and
--      loaded the waveform from the failing system-level test. I added the
--      following critical signals to the view:
--      - The main system bus signals: `bus_addr`, `bus_rdata`.
--      - The chip selects for all slaves: `ram_cs_n`, `dma_cs_n`, `crc_cs_n`, etc.
--      - The individual `rdata` outputs from the RAM and this CRC module.
--
--   3. The "Aha!" Moment: I zoomed in on the exact clock cycle where the testbench
--      was trying to read the final CRC result. I saw that `bus_addr` was
--      correctly set to `0x0002_0004`, and the `address_decoder` correctly
--      asserted `crc_cs_n` (drove it low). However, I noticed that `ram_cs_n`
--      was *not* high. An earlier version of my address decoder had a bug where
--      address ranges overlapped, causing both the RAM and the CRC module to be
--      selected simultaneously. The waveform clearly showed both peripherals
--      trying to drive their own `rdata` onto the shared `bus_rdata`, resulting
--      in contention and the 'X' value seen by the CPU.
--
-- The Fix: The fix was not in this module, but in the `address_decoder`. I
-- corrected the decoder's logic to ensure the address ranges were mutually
-- exclusive. This experience was invaluable, teaching me that the root cause
-- of a bug is often in an interacting module, and debugging requires a
-- holistic, system-level view.
--
*/