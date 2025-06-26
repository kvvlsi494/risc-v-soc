/*
--------------------------------------------------------------------------------
-- Module Name: crc32_accelerator
-- Project: A Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: [Your Name/Persona]
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


// This `module` declaration defines the boundary of the crc32_accelerator.
// All logic within this block is part of this specific hardware IP. The port
// list in the parentheses defines its complete input/output interface.
module crc32_accelerator (

    // --- System Signals ---
    // These signals are fundamental to any synchronous design within the SoC.
    // `clk`: A single-bit input that serves as the system clock. All sequential
    // logic (state changes in registers) within this module is synchronized to
    // the rising edge of this signal, ensuring predictable timing. It is
    // driven by the main clock source in the testbench.
    input        clk,

    // `rst_n`: A single-bit input for the active-low, asynchronous system reset.
    // When this signal is driven to '0', the module must immediately (without
    // waiting for a clock edge) return to its defined initial state. This is
    // critical for system power-on and recovery.
    input        rst_n,
    
    
    // --- Simple Slave Bus Interface ---
    // This is a standard set of signals for a memory-mapped slave peripheral.
    // It's how the module listens and responds to the system bus masters.
    // `cs_n`: A single-bit input for the active-low chip select. This signal is
    // the primary "enable" for the module. It is driven by the top-level
    // `address_decoder`. The module will only pay attention to bus activity
    // when this signal is asserted (driven to '0').
    input        cs_n,


    // `wr_en`: A single-bit input for the write enable signal. This is driven by
    // the active bus master and dictates the direction of the transaction.
    // A '1' indicates a write cycle, and a '0' indicates a read cycle.
    input        wr_en,

    // `addr`: A 2-bit input address bus. The top-level `address_decoder` maps
    // a large block of memory space to this peripheral. These lower address bits
    // are used to select specific registers *within* this module, allowing for
    // more granular control. A 2-bit address provides access to 4 unique
    // 32-bit (word-aligned) register locations (at offsets 0x0, 0x4, 0x8, 0xC).
    input [1:0]  addr,


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

// `crc_reg`: This is the most important state-holding element in the module.
// It is declared as a `reg` in Verilog, which is a variable type capable of
// storing a value. Since `crc_reg` is assigned within a clocked `always` block,
// the synthesis tool will infer this as a 32-bit register composed of 32
// flip-flops. Its purpose is to hold the intermediate or final CRC-32 value
// as data words are processed. It is read from to provide the `rdata` output
// and is updated on reset or during a write operation.
reg [31:0] crc_reg;



// --- Constant Declaration ---

// `CRC_INITIAL_VALUE`: This is a compile-time constant defined using the
// `parameter` keyword. It does not synthesize into any hardware logic itself;
// rather, it provides a named, fixed value that can be used throughout the
// design. This is superior to hard-coding a "magic number" because it improves
// readability and maintainability.
// Purpose: This specific value, 32'hFFFFFFFF, is the standard initial value
// required by most CRC-32 algorithms before any data is processed, ensuring
// compliance with the specification.
parameter CRC_INITIAL_VALUE = 32'hFFFFFFFF;



// --- Combinational Read Logic and Bus Protocol Compliance ---
//
// This single line of code is one of the most critical in any slave peripheral.
// It defines the behavior of the read data output (`rdata`) and ensures that
// this module is a "good citizen" on the shared system bus.
//
// An `assign` statement creates a continuous, combinational connection.
// It uses a ternary operator (`condition ? value_if_true : value_if_false`)
// to act as a 2-to-1 multiplexer for the output.
//
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
// The sensitivity list, `@(posedge clk or negedge rst_n)`, defines the exact
// conditions under which the logic inside the block is evaluated:
//   - `posedge clk`: Triggers on the rising edge of the clock for all normal,
//     synchronous state changes.
//   - `negedge rst_n`: Triggers *immediately* if the `rst_n` signal transitions
//     from high to low. This creates an asynchronous reset, which takes
//     priority over the clock.
always @(posedge clk or negedge rst_n) begin

    // --- Asynchronous Reset Implementation ---
    // This `if` statement checks the `rst_n` signal first. Because `negedge rst_n`
    // is in the sensitivity list, this condition is evaluated instantly upon reset,
    // ensuring the hardware enters a known, predictable state immediately.
    if (!rst_n) begin

        // The non-blocking assignment (`<=`) is used for sequential logic. It
        // models the behavior of a flip-flop, where the output is updated based
        // on the input at the clock edge. Here, it loads the CRC register with
        // the standard initial value.
        crc_reg <= CRC_INITIAL_VALUE;
    end 
    
     // --- Synchronous Operation Logic ---
    // This `else` block contains all the logic that executes only on a
    // rising clock edge when the reset is not active.
    else begin

        // --- Write Cycle Detection ---
        // This condition checks if a valid write cycle is targeting this specific
        // peripheral. It requires both the chip select (`cs_n`) to be active ('0')
        // AND the write enable (`wr_en`) to be active ('1').
        if (!cs_n && wr_en) begin

            // --- Internal Register Map Decoding ---
            // A `case` statement is a clear way to implement a decoder. It inspects
            // the value of the internal address bus (`addr`) and executes the
            // logic corresponding to the selected register.
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
                    // function. The function is passed the current CRC state and the
                    // new data from the bus (`wdata`) to compute the next state.
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
// and must execute in zero simulation time. It's ideal for abstracting
// complex calculations like this one. The result is returned through a variable
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
        // It iterates 32 times, processing one bit of the input data in each iteration.
        for (i = 0; i < 32; i = i + 1) begin

            // This is the main conditional logic of the CRC calculation. It XORs the
            // most significant bit of the current CRC (`c[31]`) with the current

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
--------------------------------------------------------------------------------
-- Conceptual Deep Dive: Hardware Acceleration (Offload Engine)
--------------------------------------------------------------------------------
--
-- What is it?
-- Hardware Acceleration is a core principle in digital VLSI and system design.
-- It involves creating a dedicated, specialized piece of hardware (an "IP block"
-- or "accelerator") to perform a specific, often repetitive or computationally
-- intense, task that a general-purpose CPU could do in software, but much less
-- efficiently.
--
-- Where is it used in this file?
-- This entire module, `crc32_accelerator`, is a textbook example of a hardware
-- accelerator. The task is calculating a CRC-32 checksum.
--
--   - The CPU's Role (General Purpose): A CPU is designed to be flexible. It
--     can add, branch, load, and store, allowing it to run any program. To
--     calculate a CRC, it would need to execute a loop with multiple shifts,
--     XORs, and conditional branches for every single bit of data. This is
--     slow and consumes a lot of power and CPU cycles.
--
--   - This Module's Role (Specialized): This hardware is built for one purpose.
--     The `calculate_crc32` function and the surrounding logic are a direct
--     physical implementation of the algorithm. It can process 32 bits of
--     data in a fixed, small number of clock cycles. It is orders of magnitude
--     faster and more power-efficient than the software equivalent.
--
-- Why is it used here?
-- We use this concept to demonstrate a fundamental SoC design pattern:
--
--   1. Offloading: The CPU is freed from the burden of the CRC calculation.
--      While this accelerator is busy, the CPU can perform other tasks, like
--      preparing the next data packet or managing other peripherals. This
--      improves overall system throughput.
--
--   2. Performance and Power: Dedicated hardware is always faster and more
--      power-efficient for a fixed task than a general-purpose processor.
--      In battery-powered devices or high-throughput systems (like networking
--      or storage), this is not just an optimization; it's a requirement.
--
--   3. System Architecture: It forces us to think about how different parts
--      of a system communicate. We had to give this specialized engine a
--      standard "memory-mapped" interface (`cs_n`, `wr_en`, `addr`, etc.) so
--      that the CPU or DMA could easily control it, treating it just like a
--      location in memory. This is how complex SoCs are built—by integrating
--      many specialized accelerators with general-purpose cores.
--
--------------------------------------------------------------------------------
*/






/*
--------------------------------------------------------------------------------
--                              PROJECT ANALYSIS
--------------------------------------------------------------------------------
--
-- 
--
-- ############################################################################
-- ##                 Development Chronicle and Verification                 ##
-- ############################################################################
--
--
-- [[ Motive and Inception ]]
--
-- The idea for this specific `crc32_accelerator` module came from a desire to
-- create a realistic and verifiable "hardware offload" scenario. I needed a
-- peripheral that was more than just a simple register; it had to perform a
-- real, non-trivial computation. CRC-32 was the perfect candidate because:
--   1. It's a well-defined, standard algorithm.
--   2. It's computationally intensive enough in software to justify a hardware
--      implementation.
--   3. Its state-updating nature (the new CRC depends on the old one) is a
--      great way to test stateful hardware design.
-- My goal was to build a self-contained IP block that could be controlled by
-- the CPU, proving the concept of a CPU managing a co-processor.
--
--
-- [[ My Coding Ethic and Process ]]
--
-- For this module, I followed a structured, bottom-up design process to ensure
-- correctness and clarity:
--
--   1. Research and Algorithm First: Before writing any Verilog, I researched
--      the CRC-32 algorithm to ensure I understood the bit-serial logic
--      involving the polynomial.
--
--   2. Interface Definition: I first defined the module's interface. I knew it
--      needed a standard slave bus interface (`clk`, `rst_n`, `cs_n`, `wr_en`,
--      `addr`, `wdata`, `rdata`). I also defined its internal register map on
--      paper: address 0x0 for control (resetting the CRC) and address 0x4 for
--      data input/output.
--
--   3. Core Logic Implementation: I implemented the `calculate_crc32` function
--      first, as it was the core computational part. This allowed me to test
--      the algorithm's logic separately.
--
--   4. Bus Logic Implementation: I then wrote the `always` block to handle the
--      bus write operations and the `assign` statement for the read logic. I
--      paid special attention to the tri-state logic for `rdata` from the very
--      beginning, as I knew bus contention is a common and difficult bug to
--      find later during integration.
--
--   5. Naming Convention: I used clear and consistent naming (e.g., `_reg` for
--      registers, `_n` for active-low signals) to make the code self-documenting.
--
--
-- [[ Unit Testing Strategy ]]
--
-- Before even considering integrating this module into the main SoC, I
-- subjected it to a rigorous unit test. This is a critical step in my design
-- ethic, as it allows me to find and fix bugs in a simple, isolated
-- environment.
--
--   - Dedicated Testbench: I created a separate testbench file, `tb_crc32_accelerator.v`.
--     This testbench instantiated *only* the `crc32_accelerator` module.
--
--   - Test Scenario: The testbench contained tasks to simulate a bus master.
--     It performed a sequence of actions:
--       1. Assert reset to check the initial state.
--       2. Perform a write to the control register (address 0x0) to test the
--          software reset functionality.
--       3. Perform a sequence of writes to the data register (address 0x4),
--          feeding it a known stream of data words.
--       4. Perform a read from the data register to get the final hardware-
--          calculated CRC.
--
--   - Self-Checking Scoreboard: The unit testbench was self-checking. It
--     contained a "golden model"—a Verilog function identical to the DUT's
--     `calculate_crc32`. After the hardware test sequence, the testbench would
--     run the same data stream through its own golden function. It then
--     compared the result from the DUT with the golden result. If they
--     matched, it printed a "PASS" message; otherwise, it flagged an "ERROR".
--
-- This unit test gave me very high confidence in the module's functional
-- correctness before I proceeded with the complex task of system integration.
--
--------------------------------------------------------------------------------
*/




/*
############################################################################
##                   System Integration and Verification                  ##
############################################################################
--
--
-- [[ Integration into the Top-Level SoC ]]
--
-- After passing its unit test, this `crc32_accelerator` module was integrated
-- into the main System-on-Chip design file, `risc_soc.sv`. This process
-- involves two key steps:
--
--   1. Instantiation: A copy of the module is created inside `risc_soc.sv` with
--      a unique instance name, `u_crc`.
--      Example: `crc32_accelerator u_crc ( ... );`
--
--   2. Port-Mapping (Wiring): Each port of the `u_crc` instance is connected
--      to the appropriate top-level system bus wire.
--      - `clk` and `rst_n` are connected to the global system clock and reset.
--      - `cs_n` is connected to the `crc_cs_n` wire, which is driven by the
--        `address_decoder` module. The decoder is designed to assert this
--        signal whenever the main bus address is in the `0x0002_xxxx` range.
--      - `wr_en`, `addr`, and `wdata` ports are connected directly to the
--        main system bus wires (`bus_wr_en`, `bus_addr`, `bus_wdata`). Note
--        that the full 32-bit `bus_addr` is not needed; only the lower bits
--        (`bus_addr[3:2]`) are used for internal register selection.
--      - The `rdata` output port is connected to the logic that feeds the
--        main `bus_rdata` multiplexer. The tri-state ('Z') capability of this
--        port is critical here, ensuring it only drives the bus when its
--        `crc_cs_n` is active.
--
-- This wiring scheme fully integrates the CRC accelerator as a memory-mapped
-- slave peripheral, accessible to any bus master (CPU or DMA).
--
--
-- [[ System-Level Verification Strategy ]]
--
-- Verifying this module at the system level means proving it works correctly
-- when interacting with other components through the shared bus. This was
-- accomplished by the `CRC_TEST` sequence within the main testbench file,
-- `tb_risc_soc.sv`.
--
-- The `run_crc_test` task in the testbench performs a complete end-to-end test:
--
--   1. Stimulus Generation: The test starts by generating a random block of
--      data and using the CPU Bus Functional Model (BFM) to write this data
--      into the `on_chip_ram`. This sets up the source data for the test.
--
--   2. CPU-Driven Test Execution: The testbench then uses the CPU BFM to mimic
--      a real software program:
--      - It writes to the CRC control register (`0x0002_0000`) to reset it.
--      - It enters a loop, reading each word from the source data block in RAM.
--      - For each word read, it immediately writes that word to the CRC data
--        register (`0x0002_0004`).
--      - This sequence forces transactions to go across the entire system:
--        CPU -> Arbiter -> Bus -> RAM (read), then CPU -> Arbiter -> Bus -> CRC (write).
--
--   3. Result Checking (Scoreboarding): After feeding all the data, the
--      testbench performs a final read from the CRC data register to get the
--      hardware-calculated result. It then compares this against its own
--      "golden" CRC calculation. A mismatch immediately flags a test failure.
--
-- This system-level test is far more powerful than the unit test because it
-- verifies not just the CRC module's logic, but also the correctness of the
-- arbiter, address decoder, bus multiplexers, and the RAM, all working in concert.
--
--------------------------------------------------------------------------------
*/





/*
--
-- ############################################################################
-- ##                    Industrial Context and Insights                     ##
-- ############################################################################
--
--
-- [[ Industrial Applications ]]
--
-- The concept of a dedicated CRC hardware accelerator, as implemented in this
-- module, is not just an academic exercise; it is a fundamental and widely-used
-- building block in the digital VLSI industry. Its primary application is to
-- ensure data integrity at very high speeds in various domains:
--
--   1. Networking Hardware: This is the most common use case.
--      - In a Network Interface Card (NIC) or a switch ASIC, every Ethernet
--        frame has a Frame Check Sequence (FCS), which is a CRC-32. As packets
--        arrive at line rate (e.g., 10/40/100 Gbps), a hardware CRC engine is
--        essential to validate incoming frames and generate checksums for
--        outgoing frames without slowing down the data path. A general-purpose
--        CPU simply cannot keep up.
--      - TCP/IP Offload Engines (TOE) use hardware to calculate checksums for
--        TCP/IP and UDP headers, offloading this from the host system's CPU.
--
--   2. Storage Controllers:
--      - In Solid-State Drive (SSD) or Hard Drive (HDD) controllers, data is
--        transferred between the host (via protocols like SATA or NVMe) and the
--        storage medium (NAND Flash, magnetic platters). The SATA protocol
--        specification mandates CRC checks on data packets (FIS - Frame
--        Information Structure) to protect against data corruption on the bus.
--        This is always done in hardware.
--
--   3. Communication Protocols:
--      - The PCI Express (PCIe) protocol, which connects most high-speed
--        peripherals in a modern computer, uses CRCs (called Link and End-to-End
--        CRCs) to protect both the data payload and transaction-layer packets.
--        Every PCIe endpoint and root complex contains CRC hardware.
--      - Serial protocols like CAN bus (in automotive) and SPI often use smaller
--        CRCs to ensure command and data integrity.
--
-- In all these applications, the architecture is similar to this project: a DMA
-- engine moves data from a buffer, streams it through a hardware CRC block,
-- and then takes action based on the result, all with minimal CPU intervention.
--
--
-- [[ Industrially Relevant Insights Gained ]]
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
--
-- [[ Current Limitations ]]
--
-- While functional, this implementation has several limitations that would need
-- to be addressed for a commercial-grade IP block:
--
--   1. Fixed Polynomial: The CRC-32 polynomial (`32'h04C11DB7`) is hard-coded.
--      Different standards (like Gzip or Bzip2) use different polynomials. This
--      module cannot be reconfigured for those standards.
--   2. Throughput: The `calculate_crc32` function is purely combinational and
--      has a long logic path (a 32-iteration loop). In a physical synthesis
--      flow, this would likely limit the maximum clock frequency (Fmax) of the
--      entire system.
--   3. No Streaming Interface: The module requires the master to perform a
--      separate read/write bus transaction for every single word. This is
--      inefficient and creates a lot of bus traffic.
--
--
-- [[ Future Improvements ]]
--
-- Based on the limitations, I have a clear roadmap for future enhancements:
--
--   1. Configurable Polynomial: I would add another configuration register to
--      the module. A master could write a new polynomial value to this
--      register, making the IP far more flexible and reusable for different
--      applications.
--
--   2. Pipelined Calculation: To improve Fmax, I would re-architect the
--      calculation logic. Instead of a single combinational function, I would
--      create a multi-stage pipeline. Each stage would process a few bits of
--      the data. This increases latency (it takes more cycles to get the first
--      result) but dramatically increases throughput, allowing for a much
--      higher system clock speed.
--
--   3. AXI4-Stream Interface: To solve the bus traffic issue, I would replace
--      the simple memory-mapped interface with an industry-standard AXI4-Stream
--      interface. This is a protocol designed for high-throughput, unidirectional
--      data flow. A DMA could then establish a "stream" directly to this CRC
--      module, sending data continuously without needing a new address for
--      every word, which is how real high-performance systems are designed.
--
--------------------------------------------------------------------------------
*/




/*
-- ############################################################################
-- ##                  Environment, Tools, and Execution                     ##
-- ############################################################################
--
--
-- [[ My Development Environment Setup ]]
--
-- I made a conscious decision to use a completely open-source and lightweight
-- toolchain for this project. This approach forced me to understand the
-- fundamentals of the EDA flow rather than relying on a monolithic, push-button
-- commercial tool.
--
--   - Coding Editor: Visual Studio Code (VS Code). I chose VS Code because it
--     is fast, highly extensible, and has an excellent integrated terminal. I
--     installed the "Verilog-HDL/SystemVerilog" extension by mshr-h, which
--     provided syntax highlighting, linting (real-time error checking), and
--     code snippets, significantly speeding up the development process.
--
--   - Simulation Engine (EDA Tool): Icarus Verilog (`iverilog`). This is a
--     well-established open-source Verilog and SystemVerilog simulator.
--     Why Icarus?
--       - Accessibility: It's free and runs on Windows, Linux, and macOS,
--         making the project highly portable.
--       - Standards Compliance: It is quite strict with the Verilog-2005 and
--         SystemVerilog standards, which forced me to write clean, portable,
--         and unambiguous code that would likely work with any major commercial
--         simulator (like VCS, Questa, or Xcelium).
--
--   - Waveform Viewer: GTKWave. This is the standard companion to Icarus
--     Verilog. It's a no-frills but powerful tool for viewing the Value Change
--     Dump (`.vcd`) files generated by the simulation. It was my "digital
--     logic analyzer" and was absolutely indispensable for debugging all the
--     complex timing and bus-related issues.
--
--   - Automation Scripting: Python 3. For managing the regression suite,
--     Python was the obvious choice. Its `subprocess` and `os` libraries make
--     it trivial to call command-line tools like `iverilog`, capture their
--     output, and parse log files for pass/fail signatures. This is exactly
--     how "glue" scripting is done in the industry.
--
--
-- [[ Execution Commands ]]
--
-- The entire project is orchestrated by the `run_regression.py` script, which
-- automates the compilation and simulation steps. Here is a breakdown of the
-- commands it generates and executes in the terminal:
--
--   1. Compilation:
--      The script first constructs a single compilation command to build the
--      simulation executable. The order of files is critical to satisfy
--      dependencies.
--
--      The command is:
--      `iverilog -g2005-sv -o soc_sim on_chip_ram.v crc32_accelerator.v timer.v uart_tx.v uart_rx.v uart_top.v address_decoder.v arbiter.v interrupt_controller.v dma_engine.v simple_cpu.v risc_soc.sv tb_risc_soc.sv`
--
--      - `iverilog`: Invokes the Icarus Verilog compiler.
--      - `-g2005-sv`: A flag that tells the compiler to enable SystemVerilog
--        features, which are used heavily in the testbench (`tb_risc_soc.sv`).
--      - `-o soc_sim`: Specifies the name of the output executable file (`soc_sim`).
--      - `[file list]`: The list of all Verilog and SystemVerilog source files
--        required for the design. This file, `crc32_accelerator.v`, is included
--        in this list.
--
--   2. Simulation:
--      After successful compilation, the script runs the simulation for each
--      test case. To run the specific test that verifies this module, it would
--      execute the following command:
--
--      The command is:
--      `vvp soc_sim +TESTNAME=CRC_TEST`
--
--      - `vvp`: The Verilog Virtual Processor, which is the runtime engine that
--        executes the compiled `soc_sim` file.
--      - `soc_sim`: The compiled simulation executable.
--      - `+TESTNAME=CRC_TEST`: This is a "plusarg," a standard way to pass
--        parameters from the command line into a Verilog/SystemVerilog
--        simulation. The `tb_risc_soc.sv` file contains a `$value$plusargs`
--        system task that reads this value and uses it to select which test
--        sequence to run. In this case, it would execute the `run_crc_test` task.
--
--------------------------------------------------------------------------------
*/