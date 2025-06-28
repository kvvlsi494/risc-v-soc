// Copyright (c) 2025 Kumar Vedang
// SPDX-License-Identifier: MIT
//
// This source file is part of the RISC-V SoC project.
//


/*
--------------------------------------------------------------------------------
-- Module Name: arbiter
-- Project: Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: Kumar Vedang
--------------------------------------------------------------------------------
--
-- Description:
--
-- This `arbiter` module acts as the "traffic controller" for the main system
-- bus. In any System-on-Chip (SoC) that features more than one "master" device
-- capable of initiating transactions, a mechanism is required to manage access
-- to shared resources like memory and peripherals. This module implements that
-- mechanism.
--
-- Our SoC has two such masters:
--   1. The CPU (`simple_cpu`): Fetches instructions and accesses peripherals.
--   2. The DMA Engine (`dma_engine`): Autonomously moves data blocks.
--
-- If both masters attempt to use the bus simultaneously, it would result in a
-- catastrophic "bus fight," where both try to drive the same wires, leading to
-- unknown signal values ('X' in simulation) and system failure. The arbiter
-- prevents this by implementing a clear set of rules for granting bus access.
--
-- How it works:
-- The arbiter receives request signals from each master. Based on a predefined
-- priority scheme, it grants access to only one master at a time by asserting
-- a corresponding grant signal. The winning master is then free to use the bus,
-- while the other master must wait.
--
-- Integration and Communication:
-- - Receives input from: The `m_req` (master request) output ports of both the
--   `simple_cpu` (req_0) and `dma_engine` (req_1) modules.
-- - Sends output to: The `m_gnt` (master grant) input ports of the `simple_cpu`
--   (gnt_0) and `dma_engine` (gnt_1). The grant signals are also used by the
--   top-level SoC logic to control the multiplexers that select which master's
--   signals are connected to the main bus.
--
-- Significance in the Project:
-- This module is the hardware embodiment of the concept of resource contention
-- management. While the address decoder routes traffic, the arbiter decides
-- who gets to send traffic in the first place. Its presence is what elevates
-- this design from a simple single-master system to a more realistic, complex
-- multi-master SoC.
--
--------------------------------------------------------------------------------
*/



`timescale 1ns / 1ps


// This defines the `arbiter` module, a self-contained block of digital logic.
module arbiter (

// --- System Signals ---
input clk,

input rst_n,

input req_0,  // Request from Master 0 (CPU)

input req_1,  // Request from Master 1 (DMA)


// --- Grant lines to the two masters ---
output gnt_0,  // Grant to Master 0 (CPU)

output gnt_1   // Grant to Master 1 (DMA)
);

// --- Internal Register Declarations ---
// A Verilog 'reg' is a data storage element. In this context, because it is
// being assigned inside a combinational `always @(*)` block, it does NOT
// synthesize to a flip-flop. Instead, it acts as a variable that holds the
// calculated output value before it's driven onto an output wire. This is a
// common coding style.


// This internal register will hold the calculated grant status for the CPU.
reg gnt_0_reg;


// This internal register will hold the calculated grant status for the DMA.
reg gnt_1_reg;



// --- Continuous Assignments ---
// An `assign` statement creates a permanent, continuous connection between
// two signals. It's like soldering a wire.

// This continuously drives the output port `gnt_0` with the value held
// by the internal register `gnt_0_reg`.
assign gnt_0 = gnt_0_reg;


// This continuously drives the output port `gnt_1` with the value held
// by the internal register `gnt_1_reg`.
assign gnt_1 = gnt_1_reg;





// This `always` block describes the core combinational logic of the arbiter.
// The `@(*)` is called the "sensitivity list." The asterisk is a Verilog-2001
// shorthand that tells the simulator/synthesis tool to re-evaluate the block
// whenever ANY of the signals read inside it (in this case, `req_0` and `req_1`)
// change their value. This ensures the logic behaves combinationally.
always @(*) begin

    // --- Default Assignments ---
    // At the beginning of the block, we establish a default state for the outputs.
    // This is a crucial coding practice in combinational `always` blocks. It
    // prevents the synthesis of unintended latches by ensuring that the output
    // registers are always assigned a value, no matter which path of the `if`
    // statement is taken. The default is that no grants are active.
    gnt_0_reg = 1'b0;
    gnt_1_reg = 1'b0;


    // --- Priority Logic Implementation ---
    // This `if-else if` structure creates a priority encoder.

    // Check Master 0 (CPU) Request First.
    // Because this `if` statement is first, `req_0` has the highest priority.
    // If the CPU is requesting the bus (`req_0` is '1'), this condition is met.
    if (req_0) begin

        // Grant the bus to the CPU.
        gnt_0_reg = 1'b1;

        // Explicitly deny the bus to the DMA, even if it is also requesting.
        gnt_1_reg = 1'b0;
    end


    // This `else if` is only evaluated if the condition above (`req_0`) is false.
    // This is the core of the fixed-priority scheme.

    else if (req_1) begin

        // If the CPU is NOT requesting, but the DMA (Master 1) is, then grant
        // the bus to the DMA.
        gnt_0_reg = 1'b0;
        gnt_1_reg = 1'b1;
    end

    // Note: If neither `req_0` nor `req_1` is high, neither of these conditions
    // will be met, and the grant registers will retain their default values of '0',
    // which is the correct behavior for an idle bus.
end

endmodule







/*
--------------------------------------------------------------------------------
-- Industrial Relevance and Practical Applications
--------------------------------------------------------------------------------
--
-- Where this concept is used in the Digital VLSI Industry:
-- Bus arbitration is not an optional or academic feature; it is a fundamental
-- requirement for virtually all modern SoCs. As chips integrate more and more
-- processing cores and specialized engines (IPs), the number of bus masters
-- increases, making robust arbitration logic absolutely essential.
--
-- Practical Applications:
--
-- 1.  AMBA Bus Architecture (AXI, AHB, APB): The ARM Advanced Microcontroller
--     Bus Architecture (AMBA) is the de-facto industry standard for on-chip
--     interconnects.
--       - The AXI (Advanced eXtensible Interface) protocol, used in high-
--         performance systems like mobile phone processors, has a built-in
--         arbiter as a core part of its "Interconnect" IP. This arbiter is
--         far more complex than ours, handling separate read and write channels
--         and supporting multiple outstanding transactions, but it is based on
--         the same fundamental principle of receiving requests and issuing grants.
--       - The APB (Advanced Peripheral Bus) is a simpler bus for low-bandwidth
--         peripherals. It has a single master (the "APB bridge"), so the
--         arbitration happens at a higher level, deciding which core gets to
--         access the APB bridge.
--     An engineer working at a company like ARM, Apple, or Samsung would work
--     with these complex arbiters daily.
--
-- 2.  Data Center and AI Accelerator Chips: In an AI accelerator chip from a
--     company like NVIDIA or Google, there are numerous masters contending for
--     access to high-bandwidth memory (HBM). These include:
--       - Multiple processing cores (the "tensor cores").
--       - A high-speed DMA engine to stream data from host memory.
--       - A controlling CPU core.
--     A highly sophisticated, multi-level arbiter with quality-of-service (QoS)
--     features is required to ensure that real-time processing data gets higher
--     priority than less critical background tasks. This project's arbiter is
--     the "Hello, World!" equivalent of these complex industrial components.
--
-- 3.  Automotive SoCs: In a chip for an automotive application (e.g., from NXP
--     or Infineon), safety is paramount. The arbiter might implement a scheme
--     where requests from safety-critical systems (like the braking controller)
--     are given absolute highest priority over non-critical systems (like the
--     infotainment display), regardless of fairness.
--
-- Why this code helps in an industrial context:
-- Understanding how to build a simple arbiter from scratch provides a solid
-- foundation for understanding these more complex industrial systems. It demystifies
-- what happens inside the "black box" of an AXI Interconnect. An engineer with
-- this knowledge can better reason about system performance, debug bus deadlock
-- scenarios, and understand the implications of different arbitration policies
-- on overall system throughput and latency.
--
--------------------------------------------------------------------------------
*/
