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



// A 'module' in the Verilog Hardware Description Language (HDL) is the fundamental
// building block for creating a digital circuit. It's analogous to a class in 
// object-oriented programming or an IC on a circuit board. It encapsulates a 
// specific piece of functionality with a clearly defined interface (its ports).
module address_decoder (

    // --- Input Port Declaration ---
    // This defines a port named 'addr' as an input to the module. In hardware, this
    // corresponds to a set of 32 parallel input wires.
    // The [31:0] specifies that this is a 32-bit bus, which is the standard address
    // and data width for the RV32I (RISC-V 32-bit Integer) architecture used in this project.
    // This 'addr' bus carries the physical memory address from the active bus master 
    // (CPU or DMA) that is being targeted for a read or write operation.
    input [31:0] addr,

    // --- Output Port Declarations ---
    // The following are all single-bit output ports. By default in Verilog, these are of 
    // type 'wire'. They will be driven by the combinational logic within this module.
    // The '_cs_n' suffix is a standard industry naming convention to indicate a "Chip Select,
    // active-low" signal. Active-low means the device is enabled when the signal is a logic '0'.

    // This output signal, when driven low ('0'), selects the On-Chip SRAM. It connects
    // directly to the 'cs_n' port of the 'on_chip_ram' module instance in the top-level SoC file.
    output ram_cs_n,

    // This output selects the slave configuration port of the DMA (Direct Memory Access) engine. 
    // This allows the CPU to write to the DMA's registers to set up a transfer. It connects
    // to the 's_cs_n' port of the 'dma_engine' instance.
    output dma_cs_n,

    // This output selects the CRC-32 (Cyclic Redundancy Check) hardware accelerator. It allows
    // a master to write data to the CRC unit for processing or read its current result.
    // It connects to the 'cs_n' port of the 'crc32_accelerator' instance.
    output crc_cs_n,

    // This output selects the Interrupt Controller (INTC). This is used by the CPU to read
    // the interrupt status register or to write to the controller to acknowledge and clear an interrupt.
    // It connects to the 'cs_n' port of the 'interrupt_controller' instance.
    output intc_cs_n,

    // This output selects the General-Purpose Timer peripheral. This allows the CPU to
    // configure the timer's behavior, such as setting its compare value.
    // It connects to the 'cs_n' port of the 'timer' instance.
    output timer_cs_n,

    // This output selects the unified UART (Universal Asynchronous Receiver-Transmitter) top module.
    // This allows the CPU to access both the transmitter and receiver sub-modules for serial communication.
    // It connects to the 'cs_n' port of the 'uart_top' instance.
    output uart_cs_n // Unified UART CS
);

    // This section contains the core logic of the decoder. It uses 'assign' statements,
    // which create continuous assignments in Verilog. This means the output on the left-hand
    // side will instantly and combinationally change whenever any signal on the right-hand side changes.
    // This synthesizes directly to pure combinational logic gates (comparators and multiplexers) 
    // with no clock or memory elements.

    // The logic uses a ternary operator (`condition ? value_if_true : value_if_false`), which is a
    // compact way to describe a 2-to-1 multiplexer.
    
    // Line 1: RAM Chip Select Logic
    // This line checks if the upper 16 bits of the address bus (from bit 31 down to 16)
    // are equal to the 16-bit hexadecimal value 0x0000. 
    // If the condition is true (address is in the range 0x0000_0000 to 0x0000_FFFF),
    // the 'ram_cs_n' signal is driven to a logic '0' (active). 
    // If false, it's driven to a logic '1' (inactive). This assigns a 64KB block to the RAM.
    assign ram_cs_n = (addr[31:16] == 16'h0000) ? 1'b0 : 1'b1;


    // Line 2: DMA Chip Select Logic
    // This line performs the same comparison for the DMA engine's slave port. If the upper
    // address bits match 0x0001, it activates the DMA chip select. This maps the DMA
    // configuration registers to the address range 0x0001_0000 to 0x0001_FFFF.
    assign dma_cs_n = (addr[31:16] == 16'h0001) ? 1'b0 : 1'b1;


    // Line 3: CRC Accelerator Chip Select Logic
    // This maps the CRC peripheral to the address range starting at 0x0002_0000.
    // Only when an address in this range appears on the bus will `crc_cs_n` go low.
    assign crc_cs_n = (addr[31:16] == 16'h0002) ? 1'b0 : 1'b1;


    // Line 4: Interrupt Controller Chip Select Logic
    // This maps the Interrupt Controller to the address range starting at 0x0003_0000.
    // This allows the CPU to access the INTC's status and control registers.
    assign intc_cs_n = (addr[31:16] == 16'h0003) ? 1'b0 : 1'b1;


    // Line 5: Timer Chip Select Logic
    // This maps the Timer peripheral to the address range starting at 0x0004_0000.
    assign timer_cs_n = (addr[31:16] == 16'h0004) ? 1'b0 : 1'b1;



    // Line 6: UART Chip Select Logic
    // This maps the unified UART Top module to the address range starting at 0x0005_0000.
    // Any access within this 64KB block will activate the UART's slave interface.
    assign uart_cs_n = (addr[31:16] == 16'h0005) ? 1'b0 : 1'b1; // UART at 0x0005_xxxx

endmodule





/*
--------------------------------------------------------------------------------
-- Fundamental Concept Deep Dive: Memory-Mapped I/O (MMIO)
--------------------------------------------------------------------------------
--
-- What is it?
-- Memory-Mapped I/O is a fundamental computer architecture technique where the
-- control registers of I/O (Input/Output) peripherals are "mapped" into the 
-- system's main address space. From the perspective of the CPU (or any bus 
-- master), there is no distinction between accessing a location in RAM and 
-- accessing a register in a peripheral like a UART or a DMA controller. Both
-- are accomplished using the same standard memory access instructions, such as
-- Load Word (LW) and Store Word (SW) in the RISC-V instruction set.
--
-- Where is it used in this file?
-- This entire module IS the hardware implementation of our SoC's MMIO scheme.
-- The logic below carves out specific, non-overlapping regions of the 32-bit 
-- address space and assigns them to different hardware blocks:
--
--   - Address 0x0000_0000 to 0x0000_FFFF -> On-Chip RAM
--   - Address 0x0001_0000 to 0x0001_FFFF -> DMA Engine Registers
--   - Address 0x0002_0000 to 0x0002_FFFF -> CRC Accelerator Registers
--   - ...and so on for every peripheral.
--
-- Why is it used? (Benefits)
-- The primary reason for using MMIO is architectural simplicity and elegance.
-- 1.  Simplified CPU Design: The CPU does not need a special set of I/O 
--     instructions (like the IN/OUT instructions in x86 architecture, which is
--     known as Port-Mapped I/O). The same logic that handles memory loads and 
--     stores can be used to configure and control all peripherals. This aligns
--     perfectly with the RISC (Reduced Instruction Set Computer) philosophy.
--
-- 2.  Unified Address Space: It creates a single, contiguous address space for
--     the entire system, making software development more straightforward. A 
--     pointer in C, for example, can point to a variable in RAM or directly to
--     a UART's data register.
--
-- 3.  Flexibility: It allows peripherals like the DMA engine to access other
--     peripherals directly, just as they would access memory, without needing
--     special pathways.
--
-- This `address_decoder` module is the gatekeeper that enforces this mapping in
-- hardware, making the abstract concept of an address map a physical reality.
--
--------------------------------------------------------------------------------
*/



/*
--------------------------------------------------------------------------------
-- Personal Development Process and Coding Ethic
--------------------------------------------------------------------------------
--
-- How I started:
-- The design of this `address_decoder` module did not begin with writing code.
-- It started with architectural planning on paper (or in a text document). Before
-- a single line of Verilog was written, the entire system's memory map was
-- defined. This is a critical first step in any SoC design.
--
-- Example of the planning document outline:
--
--   =================================
--   | SoC Memory Map Definition     |
--   =================================
--   | Start Addr   | End Addr     | Device                 | Size |
--   -----------------------------------------------------------------
--   | 0x0000_0000  | 0x0000_FFFF  | On-Chip SRAM           | 64KB |
--   | 0x0001_0000  | 0x0001_FFFF  | DMA Controller         | 64KB |
--   | 0x0002_0000  | 0x0002_FFFF  | CRC32 Accelerator      | 64KB |
--   | 0x0003_0000  | 0x0003_FFFF  | Interrupt Controller   | 64KB |
--   | 0x0004_0000  | 0x0004_FFFF  | General Purpose Timer  | 64KB |
--   | 0x0005_0000  | 0x0005_FFFF  | UART Top Module        | 64KB |
--   | ...          | ...          | (Reserved for future)  |      |
--   | 0xBAD_DDAA   | (Read value) | Illegal Address Access | N/A  |
--   =================================
--
-- Only after this "contract" was established did I proceed to implement it
-- in hardware. This `address_decoder.v` file is the direct, line-by-line
-- translation of that memory map table into synthesizable hardware logic.
--
-- My Coding Ethic for this Module:
--
-- 1.  Clarity and Readability Over Premature Optimization: The logic uses simple
--     `assign` statements with ternary operators. While a `case` statement could
--     also have been used, this approach is extremely clear and directly shows
--     the one-to-one mapping between an address range and a chip-select signal.
--     For a simple decoder like this, the synthesis tool will produce highly
--     efficient logic from this readable code.
--
-- 2.  Adherence to Naming Conventions: All chip-select signals are named with
--     the `_cs_n` suffix. This is a widely understood convention in the digital
--     design industry that immediately tells any other engineer that the signal
--     is a chip select and that it is active-low. This greatly improves the
--     maintainability and integration of the design.
--
-- 3.  Simplicity and Synthesizability: The module is purely combinational. There
--     are no clocks, resets, or `always @(posedge clk)` blocks. This was a
--     deliberate choice to keep the decoder as simple and fast as possible, as
--     it sits on the critical path for address resolution in the system. The code
--     is written in a style that is guaranteed to be synthesizable by any
--     standard EDA tool.
--
--------------------------------------------------------------------------------
*/




/*
--------------------------------------------------------------------------------
-- Verification Strategy and Quality Assurance
--------------------------------------------------------------------------------
--
-- How this module is tested:
-- A simple, purely combinational module like this `address_decoder` typically
-- does not require a dedicated "unit test" in the same way a complex state 
-- machine (like the DMA) would. Its logic is straightforward and can be
-- verified by inspection. However, its functional correctness is absolutely
-- critical and is therefore implicitly and exhaustively verified by the
-- entire system-level regression suite.
--
-- Every single bus transaction in every test case relies on this decoder
-- working perfectly. If the decoder were to fail, no communication would be
-- possible, and all tests would fail immediately.
--
-- How I ensured it is working properly:
-- The decoder's functionality is confirmed through the successful execution
-- of the system-level tests defined in `tb_risc_soc.sv`. Here are specific
-- examples of how different tests validate this module:
--
-- 1.  DMA_TEST & CRC_TEST: These tests involve the CPU writing to the DMA/CRC
--     configuration registers and then reading from RAM. For this to work,
--     the decoder must correctly assert `dma_cs_n` or `crc_cs_n` during the
--     configuration phase, and then correctly assert `ram_cs_n` during the 
--     data access phase. A failure in either mapping would cause an immediate
--     test failure.
--
-- 2.  TIMER_TEST & UART_LOOPBACK_TEST: These tests specifically verify the
--     interrupt system. The CPU must first write to the Timer/UART to configure
--     them, and after the interrupt, it must read the Interrupt Controller's
--     status register. This sequence validates three distinct mappings in the
--     decoder: `timer_cs_n`/`uart_cs_n` for configuration, and `intc_cs_n`
--     for the status read.
--
-- 3.  CORNER_CASE_TEST (Illegal Address Access): This is the most direct test
--     of the decoder's "negative" logic. The testbench (`tb_risc_soc.sv`)
--     instructs the CPU to read from an unmapped address (e.g., 0x9000_0000).
--     In this scenario, the `address_decoder` correctly asserts NONE of the
--     chip-select signals. This causes the read-data multiplexer in the top-level
--     `risc_soc.sv` file to select its default value (32'hBAD_DDAA). The 
--     testbench's scoreboard checks for this exact value, thus confirming that
--     the decoder correctly handles out-of-bounds addresses.
--
-- In summary, quality is assured not by a single test, but by the successful
-- operation of the entire integrated system across a comprehensive suite of
-- functional tests. This module is the foundation upon which all system-level
-- communication is built and verified.
--
--------------------------------------------------------------------------------
*/




/*
--------------------------------------------------------------------------------
-- Industrial Relevance and Practical Applications
--------------------------------------------------------------------------------
--
-- Where this concept is used in the Digital VLSI Industry:
-- The logic implemented in this `address_decoder.v` file is not just a
-- textbook example; it is one of the most fundamental and ubiquitous components
-- in nearly every digital integrated circuit, from the simplest microcontroller
-- to the most complex high-performance SoC. Any digital chip that has more 
-- than one destination for its internal bus requires an address decoder.
--
-- Practical Applications:
--
-- 1.  Application-Specific Integrated Circuits (ASICs): In a large-scale ASIC,
--     such as a networking switch chip or a mobile phone's main processor
--     (e.g., Qualcomm Snapdragon, Apple A-series), the top-level bus
--     (often an AXI or AHB bus) connects dozens or hundreds of IP (Intellectual
--     Property) blocks. A sophisticated address decoder, often called a "bus
--     interconnect matrix" or "subsystem decoder," is responsible for routing
--     transactions from the CPU clusters to the correct destination, be it the
--     DDR memory controller, the GPU, the camera interface, or the security
--     engine. This project's decoder is a simplified version of this exact
--     component.
--
-- 2.  Field-Programmable Gate Arrays (FPGAs): When designing a system on an
--     FPGA (e.g., from Xilinx/AMD or Altera/Intel), engineers often create a
--     "soft-core" processor system (like a MicroBlaze or Nios II). The toolchains
--     for these processors automatically generate an interconnect fabric that
--     includes an address decoder to connect the soft-core CPU to user-defined
--     peripherals implemented in the FPGA logic. Understanding how this decoder
--     works from the ground up, as done in this project, is essential for
--     debugging and optimizing such FPGA-based systems.
--
-- 3.  Microcontroller Units (MCUs): A standard off-the-shelf microcontroller
--     (like an ARM Cortex-M based MCU from STMicroelectronics or NXP) has its
--     datasheet filled with memory maps. These tables, which tell a programmer
--     the address of the GPIO control register or the SPI data register, are
--     the software view of an internal hardware address decoder, identical in
--     principle to the one designed here.
--
-- Why this code helps in an industrial context:
-- An engineer who has designed, integrated, and verified this block from
-- scratch has a foundational understanding of system architecture. They can
-- read a complex industrial SoC memory map and immediately visualize the
-- underlying hardware logic (comparators and multiplexers) that implements it.
-- This skill is invaluable for system integration, software driver development,
-- and hardware/software co-debugging.
--
--------------------------------------------------------------------------------
*/



/*
--------------------------------------------------------------------------------
-- Industrially Relevant Insights Gained
--------------------------------------------------------------------------------
--
-- Working on this module, despite its simplicity, provided several key insights
-- that are directly applicable to industrial VLSI design practices.
--
-- Technical Insights:
--
-- 1.  The Trade-off Between Simplicity and Flexibility: The current design uses
--     fixed-size 64KB blocks for every peripheral. This is simple to implement
--     as it only requires comparing the top 16 bits of the address.
--
--     The Insight: This is an inefficient use of address space. The DMA controller
--     only needs a handful of registers (less than 32 bytes), yet it consumes
--     a full 64KB block. A more advanced industrial decoder would implement
--     logic for variable-sized regions. For example, it might check `addr[31:10]`
--     to assign a 1KB block to a small peripheral. This would require more
--     complex comparator logic but would allow for a much more densely packed
--     memory map, which is critical in address-space-constrained systems. This
--     project highlights the engineering decision between implementation
--     simplicity and architectural efficiency.
--
-- 2.  Performance Impact of Interconnect Logic: This decoder is pure
--     combinational logic. In a real, high-speed design, the propagation delay
--     through this logic (the "address decode latency") is a critical factor
--     in the system's maximum operating frequency (Fmax).
--
--     The Insight: The "path" from the CPU's Program Counter, through the bus
--     multiplexer, through this address decoder, to a slave peripheral, and then
--     the data's return path, constitutes a critical timing path. When running
--     Static Timing Analysis (STA) after synthesis, this path would be one of
--     the first to be analyzed for timing violations. This emphasizes that even
--     simple "glue logic" is a first-class citizen in performance analysis.
--
-- Non-Technical (Process-Oriented) Insights:
--
-- 1.  The "Contract" of the Memory Map: The most profound insight is that the
--     memory map is a contract between the hardware design team, the verification
--     team, and the software/firmware team.
--
--     The Insight: Any change to this `address_decoder.v` file, no matter how
--     small, has a cascading impact. Changing the base address of the UART
--     from 0x0005_0000 to 0x0006_0000 would require:
--       a) The hardware designer to update this file.
--       b) The verification engineer to update the testbench (`tb_risc_soc.sv`)
--          which has the addresses hard-coded in its BFM calls.
--       c) The (hypothetical) firmware engineer to update their C header files
--          that define the peripheral base addresses.
--     This demonstrates the immense importance of establishing, documenting,
--     and freezing the architectural specification early in a project to avoid
--     costly, cross-functional rework. This module is the focal point of that
--     contract.
--
--------------------------------------------------------------------------------
*/






/*
--------------------------------------------------------------------------------
-- Development Environment and Toolchain
--------------------------------------------------------------------------------
--
-- This section details the complete, open-source toolchain that was set up and
-- used for the design, simulation, and verification of this project. The
-- philosophy was to use robust, widely-available tools to focus on the
-- fundamental design principles rather than vendor-specific features.
--
-- 1.  Hardware Description Language (HDL): Verilog (IEEE 1364-2001)
--     - What it is: A standardized language for describing digital hardware.
--     - Why it was used: While SystemVerilog was used for the testbench, the
--       design itself (the "Device Under Test" or DUT) was written in the
--       Verilog-2001 standard. This was a deliberate choice to enforce a
--       discipline of writing highly portable and synthesizable code that is
--       compatible with virtually any EDA tool in the industry, from simulators
--       to synthesis and Place & Route (P&R) tools.
--
-- 2.  Coding Window / Text Editor: Visual Studio Code (VS Code)
--     - What it is: A lightweight, extensible code editor from Microsoft.
--     - How it was set up: VS Code was configured with the "Verilog-HDL/
--       SystemVerilog" extension by mshr-h.
--     - Why it was used: This setup provided excellent syntax highlighting,
--       code snippets, and real-time linting (error checking), which helped
--       catch simple syntax mistakes before ever running a simulation. Its
--       integrated terminal was crucial for creating a unified workflow where
--       code could be edited, compiled, and simulated from a single window.
--
-- 3.  RTL Simulator (EDA Tool): Icarus Verilog (iverilog)
--     - What it is: A popular and highly compliant open-source Verilog simulator.
--     - How it was integrated: Icarus Verilog is a command-line tool. It was
--       called directly from the VS Code terminal or via the Python regression
--       script (`run_regression.py`) using Python's `subprocess` library.
--     - Why it was used: I chose Icarus Verilog because it is free, cross-platform
--       (works on Windows, macOS, Linux), and mature. It provides excellent
--       support for the Verilog-2001 standard and the necessary features of
--       SystemVerilog used in the testbench. It allowed me to develop this
--       entire project without needing access to expensive commercial licenses
--       (like Synopsys VCS or Cadence Xcelium).
--
-- 4.  Waveform Debugging Tool: GTKWave
--     - What it is: An open-source waveform viewer.
--     - How it was integrated: The testbench (`tb_risc_soc.sv`) includes system
--       tasks (`$dumpfile("waveform.vcd");` and `$dumpvars(0, tb_risc_soc);`)
--       that instruct the simulator to generate a Value Change Dump (.vcd) file.
--       This file, which contains the value of every signal at every time step,
--       is then opened with GTKWave for visual analysis.
--     - Why it was used: GTKWave is the standard companion to Icarus Verilog.
--       It is the "logic analyzer" for the simulated hardware. It was absolutely
--       indispensable for debugging any non-trivial issue, such as bus contention,
--       FSM state transitions, or data path timing errors. Debugging hardware
--       without a waveform viewer is practically impossible.
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
==                  FINAL DETAILED ANALYSIS: address_decoder.v
==
================================================================================
================================================================================

--- (1) File Name and Significance ---

File Name: `address_decoder.v`

What it means and why: The name is intentionally descriptive. "address" clearly
indicates its primary input and function, which is to process bus addresses.
"decoder" is the standard digital logic term for a circuit that takes an n-bit
input and asserts one of 2^n outputs. The ".v" extension signifies that the
file contains source code written in the Verilog HDL.

Significance in this project: This file is the linchpin of the entire SoC's
interconnect. While modules like the CPU and DMA are more complex, this decoder
is what enables them to function as part of a larger system. Its significance
lies in being the physical hardware manifestation of the system's architectural
memory map, acting as the primary routing logic for all bus communication. It is
the simplest, yet arguably one of the most critical, pieces of "glue logic"
in the design.

--- (2) Detailed Module Definition (`address_decoder`) ---

The `address_decoder` module is a purely combinational digital logic block designed
in Verilog. Its sole purpose is to take a 32-bit system bus address as input and
generate six individual, active-low chip-select (`_cs_n`) signals as outputs. Each
output corresponds to a specific slave peripheral in the SoC (RAM, DMA, CRC,
INTC, Timer, UART).

The internal logic is implemented using six parallel `assign` statements. Each
statement continuously evaluates a comparison: it checks if the upper 16 bits of
the input `addr` match a unique, hard-coded hexadecimal value. If a match is
found for a specific peripheral, its corresponding `_cs_n` output is driven to
logic '0' (active/selected). All other `_cs_n` outputs remain at logic '1'
(inactive/deselected). This ensures that only one slave can be selected at any
given time, preventing bus conflicts.

--- (3) Relevance, Purpose, and Main Concepts ---

Why to use this code: This code is used to create a centralized, clear, and
easily modifiable implementation of the system memory map. By isolating the
address decoding logic into its own module, the top-level SoC file (`risc_soc.sv`)
is kept cleaner, and the architectural design is more modular.

Where this code helps: It helps at the system integration stage. It correctly
routes requests from bus masters (CPU, DMA) to the intended bus slaves. Without
it, no master could talk to any slave, and the system would be non-functional.

What are the main concepts implemented and understood:
*   **Memory-Mapped I/O (MMIO):** This is the most critical concept. By implementing
    this decoder, I demonstrated a practical understanding of how to make peripherals
    appear as memory locations to a CPU, which simplifies both hardware and
    software design.
*   **Combinational Logic Design:** The module is a textbook example of pure
    combinational logic. I understood how to use `assign` statements to create
    logic that has no state or memory and whose outputs depend solely on its
--  current inputs.
*   **Bus Architecture:** I learned that a bus is more than just wires; it's a
    protocol. The chip-select signal generated by this decoder is a key part of
    the handshake protocol between master and slave.
*   **Modularity in Hardware Design:** By creating this as a separate module, I
    practiced the principle of separating concerns, which is a core tenet of
    good engineering design, both in hardware and software.

--- (4) Implementation, Integration, and Verification ---

How I started: I started with a high-level plan, creating the memory map table
as a design document. This defined the "contract" for the entire system before
any code was written. The motivation was to build a realistic, integrated system,
and a memory map is the first step in that process.

How I implemented it: I used simple `assign` statements with ternary operators
for maximum clarity and to ensure the resulting logic would be simple and fast.
The choice to compare the top 16 bits was a practical one for this project,
assigning uniform 64KB blocks to each peripheral.

How I integrated it: In the top-level `risc_soc.sv` file, an instance of this
`address_decoder` is created.
*   Its `addr` input port is connected to the `bus_addr` wire, which carries the
    address from the currently active master.
*   Each of its `..._cs_n` output ports is connected to the corresponding `cs_n`
    input port of a slave module instance. For example, `u_addr_decoder.ram_cs_n`
    is wired directly to `u_ram.cs_n`.

How I ensured it is working properly: Verification was done implicitly at the
system level. Every passing test in the `run_regression.py` suite confirms
this decoder is working. The most direct test is the `CORNER_CASE_TEST` which
attempts to read from an unmapped address (e.g., `0x9000_0000`). The testbench
then checks that the data read back is `32'hBAD_DDAA`, which is the default
value on the read bus when no chip-select is asserted. This directly validates
that the decoder correctly handles out-of-bounds addresses by not asserting any
of its outputs.

--- (5) Industrial Usage and Insights ---

Industrial Usage of this Concept: This is not just a concept; it is a fundamental
building block of virtually every complex digital chip.
*   In a modern Intel CPU or Apple M-series SoC, this principle is used in the
    "System Agent" or "Uncore" to route requests from CPU cores to peripherals
    like PCIe controllers, memory controllers, and thermal sensors.
*   In networking ASICs (e.g., from Broadcom or Marvell), a high-speed address
    decoder within the packet processing engine routes configuration commands
    to different pipeline stages or statistics counters.
*   The platform consists of a central microcontroller acting as a Device
    Under Test (DUT) and a PC acting as a Test Host. The "Test Host" in our
    project is the testbench, and the "DUT" is the `risc_soc`. The testbench
    must know the memory map to act as a proper host, and this decoder is what
    implements that map in the DUT.

Industrially Relevant Insights:
*   Technical: The address map is a critical resource. The simple decoder in
    this project wastes address space by using large, fixed-size blocks. An
    industrial design would involve a more complex decoder capable of handling
    variable-sized regions to pack the address map more efficiently, which is
    a key skill in advanced SoC design.
*   Non-Technical: Communication is key. The memory map implemented in this
    file is a specification that multiple teams (HW design, verification,
    firmware) depend on. A single-line change here without proper
    communication and documentation can break the entire project. This highlights
    the critical importance of version control, documentation, and cross-team
    collaboration in a professional environment.

--- (6) Execution Environment and Commands ---

This file, `address_decoder.v`, is not executed on its own. It is a component
that is compiled and elaborated as part of the whole SoC design. The process is
managed by the `run_regression.py` script.

The primary command used in the terminal to compile this file is initiated by the
Python script:
`iverilog -g2005-sv -o soc_sim [list_of_all_.v_and_.sv_files]`

Specifically, `address_decoder.v` is included in the `COMPILE_ORDER` list
within the Python script. After successful compilation, the script runs the
simulation with a command like:
`vvp soc_sim +TESTNAME=DMA_TEST`

During this simulation, the logic described in `address_decoder.v` is actively
running within the `soc_sim` executable, decoding addresses for every bus cycle.
================================================================================
*/
