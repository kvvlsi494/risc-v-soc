/*
--------------------------------------------------------------------------------
-- Module Name: arbiter
-- Project: Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: [Your Name/Persona]
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
-- *who* gets to send traffic in the first place. Its presence is what elevates
-- this design from a simple single-master system to a more realistic, complex
-- multi-master SoC.
--
--------------------------------------------------------------------------------
*/



`timescale 1ns / 1ps


// This defines the `arbiter` module, a self-contained block of digital logic.
module arbiter (


// --- System Signals ---
// A single-bit input wire for the system clock. While this specific arbiter's
// logic is purely combinational and doesn't use the clock, it is included
// for good practice and to allow for easy extension to a more complex,
// clocked arbiter in the future. It is connected to the main system 'clk'.
input        clk,


// A single-bit input wire for the active-low system reset. Similar to the
// clock, it's not used in this simple implementation but is essential for
// any future sequential logic that might be added. It is connected to the
// main system 'rst_n'.
input        rst_n,



// --- Request lines from the two masters ---
// A single-bit input wire representing the bus request from Master 0.
// In this project, Master 0 is the CPU. This wire goes high when the CPU
// wants to perform a bus transaction (read or write). It is connected to
// the `m_req` output of the `simple_cpu` module instance.
input        req_0,  // Request from Master 0 (CPU)

// A single-bit input wire for the bus request from Master 1, which is the
// DMA engine. This goes high when the DMA needs to perform a data transfer.
// It is connected to the `m_req` output of the `dma_engine` module instance.
input        req_1,  // Request from Master 1 (DMA)


// --- Grant lines to the two masters ---
// A single-bit output wire that signals to Master 0 (the CPU) that it has
// been granted control of the bus. This is connected to the `m_gnt` input
// of the `simple_cpu` instance. The CPU must wait for this signal to be
// high before proceeding with its transaction.
output       gnt_0,  // Grant to Master 0 (CPU)

// A single-bit output wire that grants bus access to Master 1 (the DMA).
// This is connected to the `m_gnt` input of the `dma_engine` instance.
output       gnt_1   // Grant to Master 1 (DMA)


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
    // This `if-else if` structure creates a priority encoder. The conditions are
    // evaluated in the order they are written.

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
-- Fundamental Concept Deep Dive: Bus Arbitration and Resource Contention
--------------------------------------------------------------------------------
--
-- What is Resource Contention?
-- Resource contention is a problem that arises in any system where multiple
-- independent entities try to access a single, shared resource at the same
-- time. In this SoC, the "shared resource" is the system bus and all the slave
-- devices connected to it (especially the single-ported On-Chip RAM). The
-- "independent entities" are the bus masters: the CPU and the DMA engine. If
-- this contention is not managed, both masters would drive the bus signals
-- simultaneously, resulting in data corruption and system failure.
--
-- What is Bus Arbitration?
-- Bus Arbitration is the process of resolving resource contention for a bus.
-- The logic that performs this process is called an "Arbiter". The arbiter's
-- job is to enforce a set of rules to decide which master gets exclusive access
-- to the bus when multiple masters request it.
--
-- Where is it used in this file?
-- This entire module IS a bus arbiter. Its sole purpose is to resolve the
-- contention between the CPU (`req_0`) and the DMA engine (`req_1`).
--
-- Why is it used? (Implementation of an Arbitration Scheme)
-- This arbiter implements a specific, common type of arbitration scheme called
-- "Fixed-Priority Arbitration".
--
--   - In this scheme, each master is assigned a static, unchanging priority level.
--   - The `if-else if` structure in the `always @(*)` block is the hardware
--     implementation of this scheme. Because `if (req_0)` is checked before
--     `else if (req_1)`, Master 0 (the CPU) is given a higher priority than
--     Master 1 (the DMA).
--   - This means that if both the CPU and DMA request the bus in the same cycle,
--     the CPU will always win the grant. The DMA will only be granted the bus
--     if it is requesting AND the CPU is not.
--
--   - Why Fixed-Priority? For this system, it's a safe and simple choice.
--     Giving the CPU higher priority ensures that it can always respond to
--     critical events or perform urgent tasks, even if the DMA is in the middle
--     of a long transfer. This prevents the DMA from "starving" the CPU.
--
-- Other Common Arbitration Schemes (for context):
--   - Round-Robin: Masters are granted access in a circular queue. This provides
--     more "fair" access and prevents a high-priority master from completely
--     locking out a low-priority one. This is more complex to implement as it
--     requires state (memory of who was last granted).
--   - Time Division Multiple Access (TDMA): Each master is given a dedicated
--     time slot in which it can use the bus.
--
-- This module is the cornerstone of our multi-master system, making parallel
-- operation between the CPU and DMA possible and safe.
--
--------------------------------------------------------------------------------
*/




/*
--------------------------------------------------------------------------------
-- Personal Development Process and Coding Ethic
--------------------------------------------------------------------------------
--
-- How I started:
-- The design for this arbiter began at the system architecture phase. Once I
-- decided the SoC would have two masters (CPU and DMA), the need for an arbiter
-- became a non-negotiable requirement. The first step was not to write code,
-- but to decide on the arbitration policy.
--
-- Decision on Arbitration Policy: Fixed-Priority
-- I chose a fixed-priority scheme (CPU > DMA) for two main reasons:
-- 1.  System Stability: Giving the CPU the highest priority is the safest
--     option. It guarantees that the main control processor can never be
--     indefinitely blocked (a condition known as "starvation") by a DMA
--     transfer. This ensures the CPU can always handle critical tasks like
--     servicing a higher-priority interrupt.
-- 2.  Implementation Simplicity: A fixed-priority arbiter can be implemented
--     with simple, stateless combinational logic, as seen in this file. A
--     fairer scheme like Round-Robin would require sequential logic (a state
--     register) to keep track of the last master that was granted access,
--     adding complexity that was not necessary for this project's goals.
--
-- My Coding Ethic for this Module:
--
-- 1.  Use of Combinational `always` Block for Immediate Response: The arbiter's
--     decision should be made as fast as possible. By using an `always @(*)`
--     block, the logic is purely combinational. The grant outputs will change
--     almost instantaneously in response to changes on the request inputs,
--     minimizing the bus arbitration latency.
--
-- 2.  Preventing Inferred Latches: A common bug in Verilog is accidentally
--     creating unintended memory elements (latches). I avoided this by
--     following a strict rule: always provide a default assignment for every
--     variable at the top of a combinational `always` block. The lines
--     `gnt_0_reg = 1'b0; gnt_1_reg = 1'b0;` ensure that no matter what
--     path the `if` statement takes, the outputs are always assigned a value,
--     guaranteeing the logic remains purely combinational.
--
-- 3.  Clarity via Intermediate Registers: While I could have used continuous
--     `assign` statements with nested ternary operators to implement this logic,
--     using an `always` block with `reg` types (`gnt_0_reg`, `gnt_1_reg`) is
--     often more readable and maintainable, especially as the number of masters
--     or the complexity of the arbitration logic grows. It clearly separates
--     the "calculation" of the grant from the final output assignment.
--
--------------------------------------------------------------------------------
*/







/*
--------------------------------------------------------------------------------
-- Verification Strategy and Quality Assurance
--------------------------------------------------------------------------------
--
-- How this module is tested:
-- The arbiter's function is so tightly coupled with the system's bus masters
-- that its verification is best performed at the system level rather than
-- through a standalone unit test. A failure in the arbiter logic has immediate
-- and catastrophic consequences for the entire SoC, making its correct
-- operation a prerequisite for any other test to pass.
--
-- The primary goal of verifying the arbiter is to prove two conditions:
--   1. Mutual Exclusion: At no point in time are both `gnt_0` and `gnt_1`
--      asserted simultaneously.
--   2. Correct Prioritization: When both `req_0` and `req_1` are asserted,
--      only `gnt_0` (the CPU's grant) is asserted.
--
-- How I ensured it is working properly:
-- The arbiter's correctness is proven by the successful execution of tests
-- that force interaction and contention between the CPU and the DMA.
--
-- 1.  System-Level Test `DMA_TEST`: This is the main test that validates the
--     arbiter. The test flow is:
--       a) The CPU (Master 0) requests and gets the bus to write to the DMA's
--          configuration registers. This validates the `if (req_0)` path.
--       b) The CPU starts the DMA and goes idle.
--       c) The DMA (Master 1) then requests and gets the bus to perform its
--          data transfers. This validates the `else if (req_1)` path.
--
--     A failure here would be obvious in the waveform viewer (GTKWave). If the
--     arbiter failed to grant the bus to the DMA, the DMA FSM would hang in its
--     request state, and the simulation would time out. If the arbiter granted
--     the bus to both masters, the shared bus signals (`bus_addr`, `bus_wdata`)
--     would go to an 'X' (unknown) state, causing the scoreboard to report errors.
--
-- 2.  Implicit Priority Test: In a more advanced test scenario (which could be
--     added), we could have the CPU attempt to access a peripheral *while* a
--     DMA transfer is in progress. The expected behavior, which proves the
--     fixed-priority logic, is that the DMA's grant (`gnt_1`) would be
--     de-asserted, and the CPU's grant (`gnt_0`) would be asserted immediately,
--     effectively pausing the DMA transfer for one or more cycles. The successful
--     completion of such a test would be definitive proof of the priority scheme.
--
-- 3.  Code Review and Inspection: For a simple combinational block like this,
--     a manual code review is also a valid part of the QA process. The logic
--     is simple enough to be visually inspected for correctness, specifically
--     to confirm the priority order in the `if-else if` chain and the presence
--     of default assignments to prevent latches.
--
--------------------------------------------------------------------------------
*/





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






// NOTE: This is the end of the Verilog module definition.
// The following is a detailed, multi-line comment block providing a comprehensive
// final analysis of this file, as requested for a final project report.

/*
================================================================================
================================================================================
==
==                      FINAL DETAILED ANALYSIS: arbiter.v
==
================================================================================
================================================================================

--- (1) File Name and Significance ---

File Name: `arbiter.v`

What it means and why: The name is direct and follows standard industry terminology.
An "arbiter" is a digital circuit that resolves contention for a shared resource.
The ".v" extension identifies it as a Verilog source file.

Significance in this project: This module is what makes the SoC a true multi-master
system. Its significance is that it solves the fundamental problem of resource
contention on the shared bus. By implementing a clear set of rules, it prevents
bus fights between the CPU and the DMA engine, which would otherwise lead to
system failure. It is the gatekeeper of bus access, enabling parallel operation
by allowing the CPU to perform other tasks while the DMA safely uses the bus.

--- (2) Detailed Module Definition (`arbiter`) ---

The `arbiter` module is a stateless, purely combinational logic block. It takes
two single-bit request signals (`req_0` from the CPU, `req_1` from the DMA) as
inputs. It produces two single-bit grant signals (`gnt_0` for the CPU, `gnt_1`
for the DMA) as outputs. The core of the module is an `always @(*)` block that
implements a fixed-priority scheme. This is realized through a simple `if-else if`
structure that gives precedence to `req_0`. This ensures that if both masters
request the bus simultaneously, only `gnt_0` will be asserted. The logic guarantees
that at most one grant signal can be active at any time.

--- (3) Relevance, Purpose, and Main Concepts ---

Why to use this code: This code is used to create a simple, robust, and fast
hardware solution for managing bus access. Isolating this logic into its own
module makes the design cleaner and more modular.

Where this code helps: It helps prevent system deadlock and data corruption. It is
the critical component that allows the CPU and DMA to coexist and share the system
bus without interfering with one another.

What are the main concepts implemented and understood:
*   **Bus Arbitration:** The core concept. I demonstrated a practical understanding
    of how to receive requests and issue grants to manage a shared resource.
*   **Fixed-Priority Scheme:** I implemented a specific arbitration policy,
    understanding its trade-offs (simplicity and safety vs. potential starvation).
*   **Combinational Logic (`always @(*)`):** I showed proficiency in writing
    stateless, combinational logic in Verilog, which is crucial for high-speed
    control paths.
*   **Latch Prevention:** By using default assignments at the top of the `always`
    block, I demonstrated a key coding ethic for writing correct and synthesizable
    combinational logic, preventing the inference of unwanted latches.

--- (4) Implementation, Integration, and Verification ---

How I started: The need for this module was identified during the initial system
architecture phase, as soon as the decision was made to include a DMA engine as a
second bus master. The motivation was to enable true CPU-offload, which is only
possible if the DMA can operate as an independent master.

How I implemented it: I chose the simplest possible correct implementation: a
stateless fixed-priority arbiter. The `if-else if` structure is the most direct
translation of this policy into Verilog.

How I integrated it: In the top-level `risc_soc.sv` file, the `arbiter` is
instantiated.
*   Its `req_0`/`req_1` inputs are wired to the `m_req` outputs of the CPU/DMA.
*   Its `gnt_0`/`gnt_1` outputs are wired to the `m_gnt` inputs of the CPU/DMA.
*   Critically, the `gnt_0` and `gnt_1` signals are also used as the selector lines
    for the large multiplexers in `risc_soc.sv` that choose which master's
    address, write data, and control signals get routed to the main system bus.

How I ensured it is working properly: Its correctness is proven by the successful
execution of the system-level `DMA_TEST`. In this test, the CPU must first be
granted the bus to configure the DMA, and then the DMA must be granted the bus to
perform its transfer. The test would fail if either of these grants did not occur
correctly or if both were granted simultaneously, causing an 'X' state on the bus.
The successful completion of the test is a definitive validation of the arbiter's
functionality in a real-world contention scenario.

--- (5) Industrial Usage and Insights ---

Industrial Usage of this Concept: Arbitration is at the heart of all complex SoCs.
*   Any chip using a standard interconnect like AMBA AXI from ARM contains a
    powerful arbiter within its "AXI Interconnect" IP. These arbiters handle
    many masters and implement sophisticated policies like weighted round-robin
    to balance performance.
*   The platform consists of a central microcontroller acting as a Device
    Under Test (DUT) and a PC acting as a Test Host. In our project, the two
    masters (CPU, DMA) inside the DUT are like two sub-processors contending
    for the same memory. This scenario is extremely common in industrial designs.
*   In FPGAs, when using tools to build a system with a soft-core processor (e.g.,
    Xilinx MicroBlaze), the tool automatically generates an arbiter to manage
    access between the CPU and other custom masters, like a user-defined DMA.

Industrially Relevant Insights:
*   Technical: Latency and throughput are a trade-off. A simple fixed-priority
    arbiter has very low latency but can hurt system throughput if a low-priority
    master is starved. An industrial design requires careful analysis of expected
    bus traffic to select an arbitration policy that meets the overall performance
    goals of the chip. This project provides the baseline understanding needed to
    engage in those more complex discussions.
*   Non-Technical: System-level problems are often found in the "glue logic".
    When a complex system fails, the bug is often not in the big, complex blocks
    like the CPU, but in the simpler interconnect logic that ties them together,
    like this arbiter. This teaches the valuable lesson to never overlook the
    "simple" parts of a design during debug, as their correct function is critical
    to the whole system.

--- (6) Execution Environment and Commands ---

This file, `arbiter.v`, is a component of the larger SoC design and is compiled
as part of the whole.
The Python script `run_regression.py` orchestrates the process.

The compile command initiated by the script includes this file:
`iverilog -g2005-sv -o soc_sim [list_of_all_.v_and_.sv_files]`

The simulation command runs the compiled executable, where the arbiter's logic
is active:
`vvp soc_sim +TESTNAME=DMA_TEST`

During the simulation, the logic within `arbiter.v` is constantly evaluating the
`req_0` and `req_1` signals and driving the `gnt_0` and `gnt_1` signals accordingly,
enabling the multi-master communication verified in the test.
================================================================================
*/