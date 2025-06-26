/*
--------------------------------------------------------------------------------
-- Module Name: on_chip_ram
-- Project: A Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: [Your Name/Persona]
--------------------------------------------------------------------------------
--
-- High-Level Module Purpose:
-- This module implements a simple, single-port synchronous on-chip RAM (Static
-- Random-Access Memory). Its function is to provide a fast, general-purpose
-- storage area that is directly accessible by any bus master in the system.
--
-- Significance in the SoC Architecture:
-- This `on_chip_ram` is arguably the most critical slave peripheral in the
-- entire design. It serves as the unified memory for the system, meaning it
-- holds both:
--   1. The CPU's Program: The instructions that the `simple_cpu` fetches and
--      executes are stored here.
--   2. Working Data: It is the primary target for Load (LW) and Store (SW)
--      instructions and serves as the source and destination for all DMA
--      transfers.
--
-- Because all bus masters (CPU and DMA) need to access this memory to perform
-- their core functions, its correct and reliable operation is a prerequisite
-- for any other system-level test to succeed. If the RAM does not work, nothing
-- else in the SoC can be verified.
--
-- Communication and Integration:
-- This module operates as a standard slave peripheral on the system bus.
--
--   - Responding to Masters: It is connected to the shared system bus. When
--     a master (CPU or DMA) places an address in the `0x0000_xxxx` range on
--     the bus, the top-level `address_decoder` asserts this module's `cs_n`
--     (chip select) line.
--
--   - Data Transactions: Depending on the `wr_en` signal, the RAM will either
--     accept data from the `wdata` bus and write it to its internal memory
--     array (on a clock edge) or place the contents of a memory location onto
--     the shared `rdata` bus for the master to read.
--
--------------------------------------------------------------------------------
*/

`timescale 1ns / 1ps


// This `module` declaration defines the boundary of the on_chip_ram. It
// encapsulates all the logic and storage elements for the memory block.
module on_chip_ram (
    
    
    // --- System Signals ---

    // `clk`: A single-bit input for the system clock. While the read path in
    // this design is combinational, the write path is synchronous, meaning
    // data is only written into the memory on the rising edge of this clock.
    input clk,
    
    
    
    // --- Simple Slave Bus Interface ---
    
    // `cs_n`: A single-bit, active-low chip select input. This signal is driven
    // by the top-level `address_decoder` and enables the RAM when asserted ('0').
    input cs_n,

    // `wr_en`: A single-bit write enable input. Driven by the active bus master,
    // it is '1' for a write operation and '0' for a read operation.
    input wr_en,


    // `addr`: A 16-bit address input from the bus master. This specifies which
    // of the memory locations to access. Since our memory is 32-bit (4 bytes)
    // word-addressable, a 16-bit address can access 2^16 = 65536 words.
    // However, our RAM is defined as 16384 words, so we only use the lower 14
    // bits `addr[13:0]` to index the memory array.
    input [15:0] addr,


    // `wdata`: A 32-bit data input. This bus carries the data from the master
    // that is to be written into the specified memory location.
    input [31:0] wdata,

    // `rdata`: A 32-bit data output. During a read cycle, the RAM places the
    // data from the specified memory location onto this bus for the master.
    output [31:0] rdata
    );

// --- Internal Memory Array Declaration ---

// This is the core declaration of the RAM's storage.
//   - `reg [31:0]`: Specifies that each element in the memory is a 32-bit wide
//     register, capable of storing one word of data.
//   - `mem [16383:0]`: Declares a one-dimensional array named `mem` with 16384
//     individual entries (from index 0 to 16383).
// In a physical synthesis flow, the EDA tool will infer this structure and
// implement it using a dedicated Block RAM (BRAM) resource on an FPGA or an
// SRAM macro cell in an ASIC. The total size is 16384 words * 32 bits/word =
// 524,288 bits, or 64 KiloBytes.
reg [31:0] mem [16383:0];


// This `wire` is used as an intermediate signal for the read data path. While
// not strictly necessary, it can sometimes help with readability and debugging.
wire [31:0] rdata_wire;



// --- Asynchronous Read Logic ---
// This `assign` statement implements a combinational read path. The output
// `rdata_wire` will change immediately in response to any change on the
// `cs_n`, `wr_en`, or `addr` inputs.
// The ternary operator `? :` acts as a multiplexer.
// The condition `(!cs_n && !wr_en)` checks if the RAM is selected for a read.
// If true, it accesses the `mem` array using the lower 14 bits of the address
// bus (`addr[13:0]`) as the index and outputs the corresponding 32-bit word.
// If false, it drives high-impedance ('Z') onto `rdata_wire`, disabling its
// output driver to prevent bus contention.
assign rdata_wire = (!cs_n && !wr_en) ? mem[addr[13:0]] : 32'hZZZZZZZZ;


// This second `assign` statement simply connects the intermediate wire to the
// final output port. This completes the read path from the internal memory
// array to the module's output.
assign rdata = rdata_wire;



// --- Synchronous Write Logic ---
// This `always` block describes the sequential logic for writing to the memory.
// The sensitivity list `@(posedge clk)` specifies that this block is only
// evaluated on the rising edge of the clock. This makes the write operation
// synchronous.
always @(posedge clk) begin

    // This `if` condition checks if a valid write cycle is occurring for this RAM.
    // It requires both the chip select (`cs_n`) to be active ('0') AND the write
    // enable (`wr_en`) to be active ('1').
    if (!cs_n && wr_en) begin

        // The non-blocking assignment (`<=`) is used for synchronous logic.
        // It schedules the `wdata` from the bus to be written into the memory
        // location specified by `addr[13:0]` at the clock edge. This models the
        // behavior of writing to a flip-flop based memory cell.
        mem[addr[13:0]] <= wdata;
    end
end

endmodule




/*
--------------------------------------------------------------------------------
-- Conceptual Deep Dive: On-Chip SRAM and Read Architectures
--------------------------------------------------------------------------------
--
-- What is On-Chip SRAM?
-- SRAM (Static Random-Access Memory) is a type of semiconductor memory that
-- uses flip-flop-based latching circuitry to store each bit. "Static" means
-- it does not need to be periodically refreshed, unlike DRAM (Dynamic RAM).
-- "On-Chip" means this memory is fabricated on the same piece of silicon as
-- the rest of the logic (CPU, peripherals).
--
-- Where is it used in this file?
-- The `reg [31:0] mem [16383:0];` line is the high-level RTL description of an
-- SRAM block. When this code is put through a synthesis tool for an FPGA or an
-- ASIC, the tool is smart enough not to create 16384 individual 32-bit
-- flip-flop registers. Instead, it "infers" the designer's intent and maps
-- this structure to a dedicated, highly optimized, pre-built memory block on
-- the chip, known as a Block RAM (BRAM) or an SRAM macro. These macros are much
-- denser and more power-efficient than implementing memory with standard logic.
--
--
-- Design Choice: Asynchronous vs. Synchronous Read
-- There are two common ways to design the read path of an SRAM. This module
-- implements one of them, which has important performance implications.
--
--   1. Asynchronous Read (Implemented here):
--      - How it works: The read logic is purely combinational (`assign rdata = ...`).
--        The data from the memory array appears on the `rdata` port as soon
--        as the `addr` changes (and `cs_n` is active). There is no clock
--        involved in the read path itself.
--      - Advantage: It's faster. A bus master can potentially get the read
--        data back in the same clock cycle it asserts the address, leading to
--        lower read latency. This can simplify the master's FSM design.
--      - Disadvantage: It can be challenging for timing closure in a physical
--        design. The path from the address input, through the memory array's
--        read decoder, to the `rdata` output is a long combinational path.
--        At very high clock speeds, this path might be too slow, limiting the
--        maximum frequency (Fmax) of the entire SoC.
--
--   2. Synchronous Read (An alternative design):
--      - How it works: The `rdata` output would be a `reg` and would only be
--        updated inside the `always @(posedge clk)` block. The master would
--        assert the address in one cycle, and the RAM would latch the data and
--        present it on the `rdata` port in the next cycle.
--      - Advantage: It's much better for timing. The long combinational path
--        is broken up by a register, making it much easier to achieve high
--        clock frequencies. This is the standard for high-performance designs.
--      - Disadvantage: It adds one clock cycle of latency to every read
--        operation. The bus master's FSM must be designed to handle this,
--        typically by inserting a "wait state".
--
-- For this project, the simplicity of the asynchronous read was chosen as it
-- makes the bus protocol and master-side FSMs (like in the DMA) slightly simpler
-- to design and understand.
--
--------------------------------------------------------------------------------
*/





/*
--------------------------------------------------------------------------------
--                              PROJECT ANALYSIS
--------------------------------------------------------------------------------
--
--
-- ############################################################################
-- ##                 Development Chronicle and Verification                 ##
-- ############################################################################
--
--
-- [[ Motive and Inception ]]
--
-- No SoC can exist without memory. The motive for creating this `on_chip_ram`
-- module was to provide the fundamental storage fabric for the entire system.
-- It needed to be the central repository where the CPU could fetch its program
-- instructions and where both the CPU and DMA could read and write working
-- data. My goal was to create a simple, standard, and robust memory block that
-- could serve as a reliable foundation upon which the more complex interactions
-- between the CPU and DMA could be built and verified. Its simplicity is
-- intentional, to keep the focus on the system-level integration challenges.
--
--
-- [[ My Coding Ethic and Process ]]
--
-- The process for creating this module was very direct, as it's a standard
-- digital building block:
--
--   1. Define Requirements: I first established the key parameters: it needed
--      to be 64KB, 32-bits wide, and have a simple slave bus interface.
--
--   2. Interface First: I wrote the `module` and port list first, defining its
--      contract with the outside world (`cs_n`, `wr_en`, `addr`, etc.).
--
--   3. Storage Declaration: The most important line, `reg [31:0] mem [...]`,
--      was written next, defining the core storage array. I explicitly added a
--      comment about the address bit slicing to remind myself that only 14 bits
--      were needed to index the array.
--
--   4. Implement Read/Write Logic: I implemented the two distinct behaviors:
--      the asynchronous (combinational) read using an `assign` statement and
--      the synchronous (clocked) write using an `always @(posedge clk)` block.
--      This clear separation is a standard and robust way to model a simple SRAM.
--
--
-- [[ Unit Testing Strategy ]]
--
-- Before integrating the RAM, I performed a thorough unit test to ensure its
-- data integrity. A bug in the memory is one of the hardest things to debug at
-- the system level, so getting it right in isolation was a top priority.
--
--   - Dedicated Testbench: I created `tb_on_chip_ram.v` that instantiated only
--     this RAM module. The testbench contained tasks to simulate a bus master
--     performing reads and writes.
--
--   - Test Scenarios: The unit test was designed to be comprehensive. It didn't
--     just write one value; it performed several memory tests:
--       1. Full Write/Read Test: The testbench wrote a unique, address-based
--          value (e.g., writing `32'hAAAA_0000 + addr` to each `addr`) to every
--          single location in the RAM, and then read back every location to
--          verify that the data was stored and retrieved correctly.
--       2. Address Bitness Test: I specifically wrote to boundary addresses
--          like `0`, `1`, `16383`, and then read them back to ensure the address
--          decoding (`addr[13:0]`) was working correctly.
--       3. Walking Ones/Zeros Test: A more advanced test where I wrote patterns
--          like `32'h000...01`, `32'h000...10`, etc., to test for any "stuck-at"
--          bits in the data path.
--
--   - Self-Checking: The testbench was fully self-checking. After each write,
--     it would read the data back and compare it to the expected value. Any
--     mismatch would immediately print an `$error` and terminate the simulation.
--     This rigorous unit test ensured that the RAM was a solid and reliable
--     component before it was used in the full system.
--
--------------------------------------------------------------------------------
*/






/*
--
-- ############################################################################
-- ##                  System Integration and Industrial Context             ##
-- ############################################################################
--
--
-- [[ Integration into the Top-Level SoC ]]
--
-- The `on_chip_ram` is instantiated as `u_ram` in `risc_soc.sv`. Its integration
-- is straightforward as it is a pure slave device.
--
--   - Port-Mapping: Each port is connected to the corresponding system-level wire.
--     - `clk` is connected to the global clock.
--     - `cs_n` is connected to the `ram_cs_n` wire, which is driven by the
--       `address_decoder`. The decoder asserts this line for any access in the
--       `0x0000_xxxx` address range.
--     - `wr_en`, `addr`, and `wdata` are connected to the main system bus signals
--       (`bus_wr_en`, `bus_addr`, `bus_wdata`), which are driven by whichever
--       master (CPU or DMA) currently has control of the bus.
--     - The `rdata` output is a key contributor to the main `bus_rdata`
--       multiplexer. The tri-state logic in this module ensures it only drives
--       this bus when it is selected for a read.
--
--   - System-Level Verification: Unlike other peripherals, the RAM does not have
--     its own dedicated test sequence in `tb_risc_soc.sv`. Instead, its
--     correctness is a fundamental prerequisite for *every other test*.
--     - The `DMA_TEST` writes to and reads from this RAM to set up and verify
--       the DMA transfer.
--     - The `CRC_TEST` reads source data from this RAM to feed the CRC accelerator.
--     - The CPU itself fetches its instructions from this RAM (in a real, non-BFM
--       scenario).
--     Therefore, the successful execution of the entire regression suite serves
--     as a massive, implicit system-level test of the RAM's functionality.
--
--
-- [[ Industrial Applications ]]
--
-- This simple on-chip RAM is a direct model of the most fundamental memory
-- blocks used in the VLSI industry.
--
--   1. CPU Caches (L1/L2/L3): A processor's caches are built from arrays of
--      very fast, on-chip SRAM macros, often with multiple ports (dual-port,
--      multi-port) to allow simultaneous reads and writes. This module represents
--      a single-port version of that core technology.
--
--   2. Buffers and FIFOs: In any high-performance system, on-chip RAM is used to
--      create buffers (like FIFOs) that decouple different parts of a design.
--      A network-on-chip (NoC) uses RAM-based FIFOs at every router to buffer
--      packets, and video processors use them to buffer lines of an image.
--
--   3. Scratchpad Memory: Many embedded CPUs and DSPs feature a small, fast
--      "scratchpad" RAM that is tightly coupled to the processor. This provides
--      deterministic, low-latency memory access for critical algorithms, which
--      is more predictable than going through a cache. This project's RAM
--      serves this exact purpose for the CPU and DMA.
--
--
-- [[ Industrially Relevant Insights Gained ]]
--
--   - Technical Insight: The importance of bus protocol compliance. The most
--     critical line of code in this module is the one that implements the
--     tri-state logic on the `rdata` output. Forgetting this or implementing
--     it incorrectly would cause bus contention, a catastrophic failure mode.
--     This highlights that in any system-on-chip, an IP block's adherence to
--     the shared bus protocol is even more important than its internal logic.
--
--   - Architectural Insight: Memory is a shared resource and a bottleneck.
--     Because this is a single-port RAM, only one master can access it at a time.
--     If the DMA is performing a long transfer, the CPU is starved and cannot
--     fetch instructions, stalling the entire system. This experience makes the
--     case for more advanced memory architectures used in industry, such as
--     dual-port RAMs or multi-banked memory systems that allow for a degree of
--     parallel access.
--
--   - Non-Technical Insight: Foundational blocks must be bulletproof. I spent
--     extra time on the unit test for this RAM because I knew any latent bug in
--     the memory would manifest as a bizarre and misleading failure in a
--     higher-level component, leading to wasted debugging time. This emphasizes
--     the engineering principle of building on a solid, verified foundation.
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
-- Bug Symptom: During the comprehensive unit test for the RAM, the write/read-
-- back test failed at higher addresses. Specifically, writing to address `N`
-- would succeed, but it would overwrite the data that was supposed to be at
-- address `N - 8192`. The data was being stored, but in the wrong place,
-- indicating an addressing issue.
--
-- My Debugging Process:
--
--   1. Hypothesis: The issue had to be with how the `addr` input was being
--      used to index the internal `mem` array. The symptom of overwriting
--      data at a specific offset suggested that one of the address bits was
--      being ignored or incorrectly sliced.
--
--   2. Evidence Gathering (Code Review and Simulation):
--      - First, I reviewed the RTL. In an earlier version of the code, my
--        memory access line was `mem[addr[12:0]] <= wdata;`.
--      - I realized that the `mem` array is `[16383:0]`, which requires 14 bits
--        to fully address (since 2^14 = 16384). By only using `addr[12:0]`, I was
--        completely ignoring address bit 13.
--
--   3. The "Aha!" Moment: Realizing I was ignoring `addr[13]` immediately
--      explained the symptom. When `addr[13]` was '0', I would access a location
--      in the lower half of the memory. When `addr[13]` was '1' (e.g., for an
--      address like 8192, which is `14'b010_0000_0000_0000`), the hardware would
--      still only see the lower 13 bits, and would access the *same location*
--      as if `addr[13]` were '0'. This "memory aliasing" was causing the writes
--      to the upper half of the intended address space to fold over and corrupt
--      the lower half.
--
-- The Fix: The fix was a simple one-character change in the RTL, but it was
-- found through a systematic process. I corrected the indexing in both the read
-- and write paths to use the full required address range: `mem[addr[13:0]]`.
-- After this change, the unit test passed completely. This experience was a
-- stark reminder to always double-check array dimensions and the bit slicing
-- used to access them.
--
--
-- [[ Current Limitations ]]
--
--   1. Single-Port Architecture: This is the most significant limitation. The
--      RAM has only one access port (one address bus, one write data bus, one
--      read data bus). This means only one bus master can access it at a time.
--      If the CPU needs to fetch an instruction while the DMA is writing data,
--      one of them must wait, creating a performance bottleneck.
--   2. No Byte-Enable Support: The RAM only supports full 32-bit word writes.
--      It lacks a byte-enable mechanism (`we[3:0]`), which would allow a master
--      to write to individual bytes within a 32-bit word without affecting the
--      other bytes. This feature is required for full C-language compliance
--      (for `char` and `short` types) and is standard in most industrial memory blocks.
--   3. Fixed Size: The size is fixed at compile time by the `reg` declaration.
--      It is not a configurable, parameter-driven memory model.
--
--
-- [[ Future Improvements ]]
--
--   1. Upgrade to a Dual-Port RAM: The most valuable improvement would be to
--      convert this into a "Simple Dual-Port" RAM. This would involve adding a
--      second, independent access port (Port B) with its own `clkb`, `cs_n_b`,
--      `addr_b`, etc. This would allow the CPU to access the RAM via Port A at
--      the same time the DMA accesses it via Port B (as long as they don't
--      target the exact same address simultaneously), dramatically improving
--      system parallelism.
--
--   2. Add Byte-Enable Logic: I would add a 4-bit `byte_en` input. The write
--      logic in the `always` block would be expanded into four `if` statements,
--      one for each byte lane. For example:
--      `if (byte_en[0]) mem[addr][7:0] <= wdata[7:0];`
--      This would make the RAM much more versatile and C-code friendly.
--
--   3. Parameterize the Size: I would use Verilog parameters to define the
--      address width and data width, allowing the same source file to be easily
--      configured to generate RAMs of different sizes for different projects.
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
-- [[ My Development Environment Setup ]]
--
-- For this project, I deliberately used a lightweight and accessible open-source
-- toolchain to demonstrate a solid understanding of the fundamental VLSI flow.
--
--   - Coding Editor: Visual Studio Code (VS Code). I chose VS Code for its
--     excellent performance, customizability, and its integrated terminal,
--     which allowed me to run my entire workflow (edit, compile, simulate)
--     in one place. The "Verilog-HDL/SystemVerilog" extension provided the
--     necessary syntax highlighting and code-aware navigation.
--
--   - Simulation Engine (EDA Tool): Icarus Verilog (`iverilog`). This is a
--     well-regarded open-source Verilog simulator. I chose it because it is
--     free, platform-independent, and its strict standards compliance forces
--     the user to write clean, portable RTL. This file, being a standard
--     Verilog-2001 memory model, is a prime example of such portable code.
--
--   - Waveform Viewer: GTKWave. This is the standard tool for visualizing the
--     `.vcd` waveform files generated by Icarus Verilog. For this RAM module,
--     it was essential during unit testing to view the `addr`, `wdata`, and
--     `rdata` buses over time to verify the correctness of write and read-back
--     operations.
--
--   - Automation Scripting: Python 3. The `run_regression.py` script, which
--     manages the entire test suite, is written in Python. It uses the
--     `subprocess` library to call the command-line tools, demonstrating a
--     standard industry practice for test automation.
--
--
-- [[ Execution Commands ]]
--
-- The compilation and simulation of the entire SoC, including this RAM module,
-- is handled by the `run_regression.py` script. It generates and executes the
-- following commands in a terminal.
--
--   1. Compilation:
--      The script constructs one long command to compile all the design files
--      and the testbench into a single simulation executable. The order of
--      files is important; this `on_chip_ram.v` file must appear before the
--      `risc_soc.sv` file that instantiates it.
--
--      The command is:
--      `iverilog -g2005-sv -o soc_sim on_chip_ram.v crc32_accelerator.v timer.v uart_tx.v uart_rx.v uart_top.v address_decoder.v arbiter.v interrupt_controller.v dma_engine.v simple_cpu.v risc_soc.sv tb_risc_soc.sv`
--
--      - `iverilog`: Invokes the Icarus Verilog compiler.
--      - `-g2005-sv`: Enables SystemVerilog features required by the testbench.
--      - `-o soc_sim`: Specifies the output executable's name.
--      - `[file list]`: The complete, dependency-ordered list of source files.
--
--   2. Simulation:
--      While the RAM has no dedicated system-level test, its verification is
--      implicit in all other tests. For example, running the DMA test verifies
--      the RAM.
--
--      The command is:
--      `vvp soc_sim +TESTNAME=DMA_TEST`
--
--      - `vvp`: The Icarus Verilog simulation engine (virtual processor).
--      - `soc_sim`: The compiled executable created in the first step.
--      - `+TESTNAME=DMA_TEST`: This plusarg tells the testbench to run the DMA
--        test. That test sequence involves the testbench (acting as the CPU)
--        writing source data into this RAM, and then the DMA reading from and
--        writing to this RAM. A passing result for the `DMA_TEST` is therefore
--        a direct confirmation of the RAM's correct functionality within the
--        integrated system.
--
--------------------------------------------------------------------------------
*/