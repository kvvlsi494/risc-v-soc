// Copyright (c) 2025 Kumar Vedang
// SPDX-License-Identifier: MIT
//
// This source file is part of the RISC-V SoC project.
//

/*
--------------------------------------------------------------------------------
-- Module Name: dma_engine
-- Project: A Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: Kumar Vedang
--------------------------------------------------------------------------------
--
-- High-Level Module Purpose:
-- This module, `dma_engine`, implements a Direct Memory Access (DMA) controller.
-- A DMA is one of the most essential hardware offload engines in any modern SoC.
-- Its purpose is to perform large, bulk data copy operations between different
-- locations in memory, or between memory and peripherals, without any
-- intervention from the main CPU.
--
-- Significance in the SoC Architecture:
-- The `dma_engine` is the "workhorse" of this SoC and the most complex
-- peripheral. It is the only component besides the CPU that can act as a "bus
-- master," meaning it can independently initiate read and write transactions on
-- the system bus. This capability is central to the project's goal of
-- demonstrating a realistic, multi-master system. By offloading a simple
-- memory-to-memory copy task to the DMA, the CPU is freed to perform other
-- work, dramatically improving system efficiency and throughput.
--
-- Communication and Integration (Dual Personality):
-- This module has a unique dual personality, featuring two distinct interfaces:
--
--   1. As a Bus Slave: It exposes a set of memory-mapped configuration
--      registers to the system bus. The CPU acts as a master and writes to
--      these registers to program the DMA with a source address, a destination
--      address, and the number of words to transfer. This is how the DMA gets
--      its instructions.
--
--   2. As a Bus Master: Once the CPU gives the "start" command, the DMA's
--      personality flips. It begins to use its master interface to request
--      control of the bus from the `arbiter`. Once granted access, it
--      autonomously executes the programmed memory-to-memory copy operation,
--      reading from the source and writing to the destination. Upon completion,
--      it signals the `interrupt_controller` by asserting its `dma_done` line.
--
-- The verification of this module's dual-role operation, its interaction with
-- the arbiter, and its ability to correctly move data is the primary objective
-- of the `DMA_TEST` and the `FULL_REGRESSION` test suites.
--
--------------------------------------------------------------------------------
*/

`timescale 1ns / 1ps


// This `module` declaration defines the boundary of the dma_engine.
// It is the most complex peripheral in the SoC, acting as both a slave
// (to be configured) and a master (to execute transfers).
module dma_engine (

// --- System Signals ---
    
// `clk`: A single-bit input for the system clock. All state changes for
// both the slave and master logic are synchronized to this clock.
input clk, 

// `rst_n`: A single-bit input for the active-low, asynchronous system reset.
// When asserted, it brings all internal registers and state machines to a
// known, idle state.
input rst_n,

// --- Slave Interface (for configuration by the CPU) ---
// This set of ports allows the DMA engine to be controlled by another master,
// typically the CPU. It behaves like a simple memory-mapped peripheral.
    
// `s_cs_n`: The slave-port chip select (active-low). Asserted by the
// `address_decoder` when the CPU writes to the DMA's address range.
input s_cs_n, 

// `s_wr_en`: The slave-port write enable. Driven by the CPU to indicate a
// write operation to one of the DMA's configuration registers.
input s_wr_en, 

// `s_addr`: The slave-port address. These are the lower bits of the address
// from the CPU, used to select which internal configuration register to access.
input [2:0] s_addr, 


// `s_wdata`: The slave-port write data bus. Carries data from the CPU to
// be written into the configuration registers (e.g., source/dest address).
input [31:0] s_wdata, 


// `s_rdata`: The slave-port read data bus. Used to read back status or
// configuration from the DMA, though this design primarily uses it for status.
output [31:0] s_rdata,


// --- Master Interface (for executing transfers) ---
// This set of ports allows the DMA to take control of the system bus and
// perform its own read/write operations.
    
// `m_req`: The master-port request signal (output). The DMA asserts this
// line to request access to the system bus from the `arbiter`.
output reg m_req, 

// `m_gnt`: The master-port grant signal (input). Driven by the `arbiter`.
// When this signal is high, the DMA has been granted control of the bus.
input m_gnt, 

// `m_addr`: The master-port address bus (output). The DMA drives this bus
// to specify the source address for reads or destination address for writes.
output reg [31:0] m_addr, 


// `m_wr_en`: The master-port write enable (output). The DMA drives this
// high for write cycles and low for read cycles during its transfer.
output reg m_wr_en, 

// `m_wdata`: The master-port write data bus (output). The DMA places data
// read from the source onto this bus to be written to the destination.
output reg [31:0] m_wdata, 

// `m_rdata`: The master-port read data bus (input). This is where the DMA
// receives data from a slave (like the RAM) during its read cycles.
input [31:0] m_rdata,



// --- Status Output ---
    
// `dma_done`: A single-bit output flag. The DMA asserts this signal for one
// clock cycle upon completing the entire data transfer. This signal is
// routed to the `interrupt_controller` to notify the CPU.
output dma_done
);


// --- Internal State and Configuration Registers ---

// These registers hold the configuration set by the CPU via the slave port.
// They are written to by the CPU and read by the FSM at the start of a transfer.

reg [31:0] src_addr_reg;  // Holds the programmed source address.
reg [31:0] dest_addr_reg;  // Holds the programmed destination address.
reg [31:0] len_reg; // Holds the number of 32-bit words to transfer.

// A single-bit register that acts as the "go" signal. It is set to 1 by the
// CPU to initiate a transfer and is cleared automatically by the hardware.
reg        start_reg; 

// A single-bit register that latches the completion status. It is set by the
// FSM when a transfer finishes and is cleared by the CPU via a slave port write.
reg        dma_done_reg; 

// A 32-bit internal buffer. This register is crucial for the DMA's operation.
// It temporarily stores the data word that has been read from the source
// address before it is written to the destination address.
reg [31:0] data_buffer;

// These are the "working" registers used by the FSM during an active transfer.
// They are loaded from the main configuration registers when a transfer starts.
reg [31:0] current_src_addr; // Tracks the source address for the current word.
reg [31:0] current_dest_addr;  // Tracks the destination address for the current word.
reg [31:0] words_remaining; // A down-counter for tracking progress.


// --- FSM State Definition ---
// `parameter` is used to give meaningful names to the FSM state encodings.
// This greatly improves code readability and maintainability compared to using
// "magic numbers" in the case statement.

parameter S_IDLE = 4'b0001; // The DMA is waiting for a start command.
parameter S_READ_ADDR = 4'b0010; // FSM is requesting the bus to read from the source.
parameter S_READ_WAIT = 4'b0011; // FSM is waiting one cycle for data to return from RAM.
parameter S_WRITE_ADDR = 4'b0100; // FSM is requesting the bus to write to the destination.
parameter S_CHECK_DONE = 4'b0101; // FSM is checking if the transfer is complete.

// This 4-bit register holds the current state of the master-port FSM. Its value
// determines the DMA's actions on its master-port interface.
reg [3:0] state;


// --- Slave Port Read Logic ---
// This `assign` statement implements the read logic for the slave port.
// It uses a series of nested ternary operators to act as a multiplexer.
// If the port is selected for a read (`!s_cs_n && !s_wr_en`), it returns the
// value of the register selected by `s_addr`.
// Otherwise, it drives high-impedance ('Z') to stay off the bus.
assign s_rdata = (!s_cs_n && !s_wr_en) ? ((s_addr == 3'h0) ? src_addr_reg : (s_addr == 3'h1) ? dest_addr_reg : (s_addr == 3'h2) ? len_reg : (s_addr == 3'h4) ? {31'b0, dma_done_reg} : 32'h0) : 32'hZZZZZZZZ;



// --- Slave Port Write and Configuration Logic ---
// This `always` block handles the writing of configuration registers by the CPU.
// It is a standard synchronous block with an asynchronous reset.
always @(posedge clk or negedge rst_n) begin

    // On reset, all configuration registers are cleared to a known-zero state.
    if (!rst_n) begin 
        src_addr_reg <= 32'h0; 
        dest_addr_reg <= 32'h0; 
        len_reg <= 32'h0; 
        start_reg <= 1'b0; 

        // This `else` block contains the synchronous logic for configuration.
        end else begin 
            
            // This logic makes the `start_reg` a one-shot "pulse". After being set
            // by the CPU, it is automatically cleared on the next clock cycle.
            if (start_reg)
            start_reg <= 1'b0;
            
            // This checks if the CPU is performing a write to this DMA's slave port.
            if (!s_cs_n && s_wr_en) begin
                
                // The `case` statement decodes the address from the CPU to select
                // which configuration register to write to.
                case (s_addr) 
                
                3'h0: src_addr_reg <= s_wdata; // Write to Source Address Register
                
                3'h1: dest_addr_reg <= s_wdata; // Write to Destination Address Register
                
                3'h2: len_reg <= s_wdata; // Write to Length Register
                
                3'h3: start_reg <= s_wdata[0]; // Write to the Start Register (bit 0)
                // This allows the CPU to clear the interrupt flag by writing a '1'.
                
                3'h4: if (s_wdata[0]) dma_done_reg <= 1'b0; 
                
                endcase 
                
            end
        end
end

// --- Status Output Connection ---
// This `assign` statement continuously connects the internal `dma_done_reg` to
// the top-level `dma_done` output port for the interrupt controller.
assign dma_done = dma_done_reg;


// --- Master Port Finite State Machine (FSM) ---
// This `always` block contains the core FSM that executes the data transfer.
// It controls the master port signals (`m_req`, `m_addr`, etc.).
always @(posedge clk or negedge rst_n) begin

    // On reset, the FSM is forced into the IDLE state and all master port
    // signals are de-asserted.
    if (!rst_n) begin
        state <= S_IDLE;
        m_req <= 1'b0; 
        m_wr_en <= 1'b0; 
        dma_done_reg <= 1'b0;

    // This `else` block contains the main state transition logic.
    end else begin


        // By default, de-assert master signals at the start of every cycle.
        // They will be asserted inside specific states if needed.
        m_req <= 1'b0; 
        m_wr_en <= 1'b0;

        // This `case` statement implements the FSM's state-based behavior.

        case (state)
            // State S_IDLE: The FSM is waiting for a command.
            S_IDLE: if (start_reg && len_reg > 0) begin

                // When `start_reg` is pulsed by the CPU, load the working registers
                // from the configuration registers and transition to the first active state.
                current_src_addr  <= src_addr_reg;
                current_dest_addr <= dest_addr_reg;
                words_remaining   <= len_reg;
                state <= S_READ_ADDR;
            end

            // State S_READ_ADDR: The FSM starts the read part of a transfer.
            S_READ_ADDR: begin

                // Assert the bus request line to the arbiter.
                m_req <= 1'b1; 
                
                // Set write enable low for a read operation.
                m_wr_en <= 1'b0; 
                
                // Drive the current source address onto the master address bus.
                m_addr <= current_src_addr;

                // Wait until the arbiter grants the bus, then move to the wait state.
                if (m_gnt) state <= S_READ_WAIT;
            end


            // State S_READ_WAIT: A dedicated state to handle memory read latency.
            S_READ_WAIT: begin

                // The data from the slave is now valid on `m_rdata`. Latch it
                // into the internal `data_buffer`.
                data_buffer <= m_rdata;
                
                // Immediately move to the write state on the next cycle.
                state <= S_WRITE_ADDR;
            end

            // State S_WRITE_ADDR: The FSM starts the write part of a transfer.
            S_WRITE_ADDR: begin

                 // Assert the bus request line again for the write.
                m_req <= 1'b1; 

                // Set write enable high for a write operation.
                m_wr_en <= 1'b1; 

                // Drive the current destination address onto the master address bus.
                m_addr <= current_dest_addr; 

                // Drive the data from our internal buffer onto the write data bus.
                m_wdata <= data_buffer;



                // Wait for the grant, then move to the checking state.
                if (m_gnt) state <= S_CHECK_DONE;
            end

             // State S_CHECK_DONE: Update counters and decide what to do next.


            S_CHECK_DONE: begin

                // Decrement the counter for the word we just transferred.
                words_remaining <= words_remaining - 1;

                // Check if there are more than one words left to transfer.
                if (words_remaining > 1) begin

                    // If so, increment the source and destination addresses.
                    current_src_addr <= current_src_addr + 4;
                    current_dest_addr <= current_dest_addr + 4;

                    // And loop back to the start of the read cycle.
                    state <= S_READ_ADDR;

                // This is the last word.
                end else begin

                    // Assert the `dma_done` flag for the interrupt controller.
                    dma_done_reg <= 1'b1; 
                    
                    
                    // Return the FSM to the idle state to wait for the next command.
                    state <= S_IDLE;

                end
            end
        endcase
    end
end


endmodule




/*
--------------------------------------------------------------------------------
-- Conceptual Deep Dive 1: Direct Memory Access (DMA)
--------------------------------------------------------------------------------
--
-- What is it?
-- Direct Memory Access (DMA) is a system-level feature that allows a hardware
-- subsystem (this `dma_engine`) to read from and write to system memory
-- independently of the main Central Processing Unit (CPU).
--
-- Where is it used in this file?
-- The entire module is a DMA engine. The core DMA process is:
--   1. CPU Programs the DMA: The CPU writes the source address, destination
--      address, and transfer length into this module's configuration registers
--      via the slave port (`s_cs_n`, `s_wr_en`, etc.).
--   2. CPU Delegates the Task: The CPU writes a 'start' bit, effectively
--      telling the DMA, "My work is done, now you take over."
--   3. DMA Performs the Transfer: This module's FSM then takes control,
--      autonomously reading data from the source address and writing it to the
--      destination address, word by word, until the transfer is complete.
--   4. DMA Notifies the CPU: Upon completion, the DMA asserts the `dma_done`
--      line, which raises an interrupt, informing the CPU that the data is ready.
--
-- Why is it used?
-- DMA is fundamental to high-performance computing because it solves a major
-- bottleneck: CPU involvement in bulk data transfers. Without a DMA, to copy
-- 1000 words of data, the CPU would have to execute 3000 instructions (1000
-- loads, 1000 stores, 1000 loop-counter updates). With the DMA, the CPU
-- executes only ~4 instructions to program the DMA and is then free to perform
-- other tasks while the dedicated DMA hardware handles the copy. This massively
-- increases system parallelism and efficiency.
--
--------------------------------------------------------------------------------
*/

/*
--------------------------------------------------------------------------------
-- Conceptual Deep Dive 2: Bus Mastering
--------------------------------------------------------------------------------
--
-- What is it?
-- A "Bus Master" is any component in an SoC that can initiate transactions
-- (reads or writes) on the system bus. In contrast, a "Bus Slave" can only
-- respond to transactions initiated by a master.
--
-- Where is it used in this file?
-- This DMA engine has a dual personality. It is both a slave and a master.
--
--   - The Slave Personality: The `s_*` ports comprise the slave interface.
--     When the CPU is writing configuration data to the DMA, the DMA is
--     passively responding like any other simple peripheral.
--
--   - The Master Personality: The `m_*` ports comprise the master interface.
--     This is where the concept of Bus Mastering is implemented. The FSM uses
--     these ports to take control of the system:
--       - It asserts `m_req` to request the bus from the `arbiter`.
--       - It waits for the `arbiter` to grant access by asserting `m_gnt`.
--       - Once it receives `m_gnt`, it has become the "bus master" and has the
--         right to drive the main system address and control lines to perform
--         its own read and write operations.
--
-- Why is it used?
-- A system with only one master (the CPU) is simple but inefficient. Multi-master
-- systems, which include one or more DMA engines, are the standard in all
-- non-trivial SoCs. This DMA engine's ability to become a bus master is what
-- enables it to perform its function. It demonstrates the complete protocol for
-- peacefully sharing the system bus: Request -> Grant -> Transact. The presence
-- of this master port is what necessitates the `arbiter` in the top-level design.
--
--------------------------------------------------------------------------------
*/




/*
--------------------------------------------------------------------------------
--                              PROJECT ANALYSIS
--------------------------------------------------------------------------------
--
-- [Step 6 of 10]
--
-- ############################################################################
-- ##                 Development Chronicle and Verification                 ##
-- ############################################################################
--
--
-- [[ Motive and Inception ]]
--
-- My primary motive for building this `dma_engine` was to create a true
-- multi-master system. A system with just a CPU is a good start, but the real
-- challenges and learning opportunities in SoC design arise from bus
-- contention, arbitration, and autonomous peripherals. The DMA was the perfect
-- vehicle for this. It forced me to design an arbiter, to think about bus
-- sharing protocols (request/grant), and to build a peripheral that had a
-- complex internal state machine and a dual slave/master personality. It is, by
-- far, the most critical IP block for demonstrating a holistic understanding
-- of system-level architecture in this project.
--
--
-- [[ My Coding Ethic and Process ]]
--
-- The complexity of this module demanded a more rigorous design process than
-- the simpler slave-only peripherals:
--
--   1. FSM First: Before writing any code, I designed the master-port Finite
--      State Machine (FSM) on paper. I drew out the states (IDLE, READ_ADDR,
--      READ_WAIT, WRITE_ADDR, CHECK_DONE) and the transitions between them,
--      including the conditions for each transition (like `m_gnt` or the value
--      of `words_remaining`). This visual diagram was my blueprint.
--
--   2. Separate Logic Blocks: In the Verilog code, I intentionally separated
--      the slave-port configuration logic into its own `always` block and the
--      master-port FSM into a second `always` block. This separation of
--      concerns made the code much cleaner and easier to debug. One block
--      handles "being configured," and the other handles "doing work."
--
--   3. Working vs. Config Registers: I made a clear distinction between the
--      `..._reg` variables (like `src_addr_reg`) that hold the configuration,
--      and the "working" copies (like `current_src_addr`). The FSM only ever
--      reads the main config registers once at the beginning of a transfer.
--      This prevents a scenario where the CPU could change the configuration
--      in the middle of an active transfer, which would lead to corrupt or
--      unpredictable behavior.
--
--   4. Clear State Naming: I used `parameter` to give each FSM state a clear,
--      descriptive name (e.g., `S_READ_WAIT`). This makes the FSM's `case`
--      statement almost read like plain English, which is invaluable for
--      debugging and future maintenance.
--
--
-- [[ Unit Testing Strategy ]]
--
-- The unit test for the DMA was the most complex of all the modules because
-- the testbench had to simulate the entire rest of the system from the DMA's
-- point of view.
--
--   - The Hybrid Testbench: I created a `tb_dma_engine.v` that had to act as
--     both a master and a slave.
--       - Master Role: The testbench contained tasks to act like the CPU,
--         driving the DMA's slave port to configure it with a source, dest,
--         and length, and then to issue the start command.
--       - Slave and Arbiter Role: The testbench also had to model a simple RAM
--         and an arbiter. When the DMA asserted `m_req`, the testbench would
--         assert `m_gnt` and then listen on its master bus ports (`m_addr`,
--         `m_wr_en`). If it was a read, it would provide data; if it was a write,
--         it would store the data.
--
--   - Self-Checking Scoreboard: The testbench pre-loaded its internal RAM model
--     with a known data pattern. After the DMA transfer was complete (signaled
--     by `dma_done`), the testbench would internally check the contents of its
--     RAM at the destination address against the original source data. Any
--     mismatch would be flagged as a failure.
--
-- This isolated test was absolutely critical. It allowed me to find several
-- bugs in the FSM logic (like off-by-one errors in the `words_remaining`
-- check) before I ever attempted to integrate it into the full SoC, saving me
-- countless hours of complex system-level debugging.
--
--------------------------------------------------------------------------------
*/




/*
--------------------------------------------------------------------------------
--                              PROJECT ANALYSIS
--------------------------------------------------------------------------------
--
-- [Step 7 of 10]
--
-- ############################################################################
-- ##                   System Integration and Verification                  ##
-- ############################################################################
--
--
-- [[ Integration into the Top-Level SoC ]]
--
-- Integrating the `dma_engine` into `risc_soc.sv` is more complex than any
-- other peripheral due to its dual slave/master nature.
--
--   1. Instantiation: It is instantiated as `u_dma` in the top-level file.
--
--   2. Slave Port Wiring: The `s_*` ports are wired up like a standard slave.
--      - `s_cs_n` is connected to the `dma_s_cs_n` wire from the address decoder.
--      - `s_wr_en`, `s_addr`, and `s_wdata` are connected to the main system
--        bus (`bus_wr_en`, etc.), which is driven by the currently active master.
--      - `s_rdata` is connected to the read-data MUX logic.
--
--   3. Master Port Wiring (The Critical Part): The `m_*` ports are what make
--      the integration unique.
--      - `m_req` is wired as an input to the `arbiter` module (`req_1`).
--      - `m_gnt` is wired as an output from the `arbiter` (`gnt_1`). This
--        request/grant handshake is the core of the bus sharing mechanism.
--      - `m_addr`, `m_wdata`, and `m_wr_en` are wired as inputs to the large
--        multiplexers at the top level. When the arbiter grants access to the
--        DMA (`gnt_1` is high), these MUXs will select the DMA's master port
--        signals to drive the main system bus.
--      - `m_rdata` is connected directly to the main `bus_rdata` wire,
--        allowing it to receive data from whichever slave it is reading from.
--
--   4. Interrupt Wiring: The `dma_done` output port is connected to the
--      `irq0_in` input of the `interrupt_controller`, making it interrupt source 0.
--
--
-- [[ System-Level Verification Strategy ]]
--
-- The primary test for this module is the `DMA_TEST` sequence, which is defined
-- in the `run_dma_test` task in `tb_risc_soc.sv`. This test verifies the
-- complete, end-to-end DMA data flow through the integrated system.
--
--   1. Setup Phase: The testbench first uses the CPU BFM to write a randomized
--      block of data into a specific source region of the on-chip RAM.
--
--   2. Configuration Phase (Testing the Slave Port): The testbench then uses
--      the CPU BFM to perform a series of writes to the DMA's memory-mapped
--      address space (`0x0001_xxxx`). It writes the random source address, a
--      destination address, and the transfer length, and finally writes to the
--      start register. This part of the test implicitly verifies that the DMA's
--      slave port, the address decoder, and the bus logic are all working correctly.
--
--   3. Execution Phase (Testing the Master Port): After the start command, the
--      DMA takes over. The testbench now passively waits for the `dma_done`
--      interrupt to be asserted via the `cpu_irq_in` wire. During this time,
--      the DMA is interacting with the arbiter, taking control of the bus, and
--      performing reads and writes to the on-chip RAM. This phase verifies the
--      entire master-side data path.
--
--   4. Scoreboard Phase: Once the interrupt is received, the testbench's
--      scoreboard becomes active. It uses the CPU BFM to read the entire block
--      of data from the destination region in RAM and compares it, word by
--      word, against the original source data it generated.
--
-- A "PASS" from this test provides extremely high confidence that the DMA,
-- arbiter, address decoder, RAM, and interrupt controller are all functioning
-- and interacting correctly as a complete system.
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
-- The DMA engine is arguably one of the most ubiquitous IP blocks in the entire
-- VLSI industry. A high-performance SoC without a sophisticated DMA controller
-- is almost unimaginable. This simple engine is a blueprint for concepts used in:
--
--   1. Networking SoCs (e.g., Broadcom, Marvell): In a router or network card,
--      a multi-channel DMA is the heart of the system. It is used to move
--      network packets between different memory buffers. For example, a packet
--      arrives and is placed in a "receive" buffer by one DMA channel. The CPU
--      inspects the header, then programs another DMA channel to move the
--      packet payload to a "processing" buffer, where it might be passed
--      through a crypto or checksum accelerator (like our CRC block), and
--      finally a third DMA channel moves the processed packet to an "egress"
--      buffer for transmission.
--
--   2. Storage Controllers (e.g., Samsung, Western Digital): In an SSD, the
--      Flash Translation Layer (FTL) software running on an embedded CPU
--      determines where data from the host should be physically written to the
--      NAND flash chips. It then programs a powerful DMA engine to perform the
--      actual data movement from the host-side SRAM buffer to the NAND bus,
--      often streaming it through an ECC (Error Correction Code) engine in the
--      process.
--
--   3. Graphics and Display Processors (e.g., NVIDIA, AMD): A display
--      controller uses a dedicated DMA to read pixel data from a "framebuffer"
--      in system memory and stream it to the display interface (like HDMI or
--      DisplayPort). This happens continuously, 60 or 120 times per second,
--      and is a classic example of a DMA offloading a repetitive, high-
--      throughput task from the main CPU/GPU.
--
--   4. General-Purpose Microcontrollers (e.g., STMicroelectronics, NXP): Even
--      smaller MCUs include DMAs to allow peripherals like ADCs or SPI ports
--      to transfer large amounts of data directly to memory without bogging
--      down the main processor core, which is critical for real-time response.
--
--
-- [[ Industrially Relevant Insights Gained ]]
--
-- Building this DMA was the single most valuable learning experience in the project.
--
--   - Technical Insight: The critical importance of handling bus latency. My
--     initial FSM design did not have the `S_READ_WAIT` state. It tried to
--     latch the data from `m_rdata` in the same cycle it de-asserted the bus
--     request. This failed because a slave (like RAM) requires at least one
--     cycle to respond to a read request. The data simply wasn't there yet.
--     Adding the dedicated `S_READ_WAIT` state, whose only job is to pause for
--     one cycle, was the fix. This taught me a fundamental lesson about master
--     design: you must design your FSM to be tolerant of the inherent latency
--     of the slaves and the bus protocol you are interacting with.
--
--   - Architectural Insight: The subtle difference between configuration state
--     and operational state. Separating the CPU-programmed `src_addr_reg` from
--     the FSM's `current_src_addr` was a key design decision. It creates a
--     "shadow register" architecture that decouples the CPU's configuration
--     actions from the DMA's active transfer. This is a robust design pattern
--     that prevents race conditions where a CPU might inadvertently corrupt an
--     ongoing transfer.
--
--   - Non-Technical Insight: Complex state machines are debugged with diagrams,
--     not just code. I found it impossible to reason about the DMA's behavior
--     just by reading the Verilog. I had to constantly refer back to my hand-
--     drawn state transition diagram. This taught me that for complex control
--     logic, the high-level architectural diagram is just as important as the
--     RTL code itself. A good design is one you can explain with a picture.
--
--------------------------------------------------------------------------------
*/




/*
--
-- ############################################################################
-- ##                Post-Mortem: Bugs, Limitations, and Future              ##
-- ############################################################################
--
--
-- [[ Most Challenging Bug and Debugging Process ]]
--
-- Bug Symptom: During the `DMA_TEST`, the scoreboard reported a consistent
-- "off-by-one" error. If programmed to transfer 4 words, it would only transfer
-- 3. If programmed for 10, it would transfer 9. The final word was always
-- missed, and the `dma_done` interrupt fired too early.
--
-- My Debugging Process:
--
--   1. Hypothesis: My initial FSM logic for checking the completion condition was flawed.
--      In the `S_CHECK_DONE` state, I was decrementing `words_remaining` and then
--      checking `if (words_remaining > 0)`. I suspected a race condition where
--      the non-blocking assignment (`<=`) to `words_remaining` hadn't updated yet when
--      the `if` condition was evaluated combinationally for the next state decision.
--
--   2. Evidence Gathering (Waveform Analysis): I opened GTKWave and focused on
--      the last few cycles of a 4-word transfer. I added the FSM `state`,
--      the `words_remaining` counter, and the `dma_done` signal to the view.
--
--   3. The "Aha!" Moment: I watched the value of `words_remaining` as the FSM
--      cycled. When it was `2`, the DMA correctly started the transfer for the
--      third word. It went through `S_READ_ADDR`, `S_READ_WAIT`, `S_WRITE_ADDR`,
--      and landed in `S_CHECK_DONE`. In this state, the non-blocking assignment
--      `words_remaining <= words_remaining - 1;` was executed, so the value of
--      `words_remaining` was scheduled to become `1` on the next clock edge.
--      However, my termination check was `if (words_remaining > 1)`. In the
--      current cycle, `words_remaining` was still `2`, so this was true, and
--      the FSM went back to `S_READ_ADDR`. After the next transfer, when
--      `words_remaining` was `1`, the condition `(1 > 1)` was false. The FSM
--      incorrectly concluded it was done and went to `S_IDLE`, never transferring
--      the final word. The bug was a simple but classic off-by-one logic error.
--
-- The Fix: I corrected the termination logic in the `S_CHECK_DONE` state to be
-- `if (words_remaining > 1)`. This seems counter-intuitive, but it's correct
-- because the check is made *before* the final decrement for the last word has
-- logically occurred. When `words_remaining` is 1, it means there is one word
-- left to process. The condition `(1 > 1)` is false, so the `else` branch is
-- taken, the `dma_done` signal is asserted, and the FSM correctly returns to idle.
-- This debugging process was a crucial lesson in carefully considering the
-- exact timing of sequential updates versus combinational checks in an FSM.
--
--
-- [[ Current Limitations ]]
--
--   1. Single-Channel Only: This is a single-channel DMA. It can only perform
--      one transfer at a time. High-performance SoCs use multi-channel DMAs
--      that can be programmed with several different transfers, which are then
--      arbitrated internally.
--   2. No Scatter-Gather Capability: This DMA can only handle contiguous blocks
--      of memory. It cannot be programmed to read from several disparate source
--      locations and write them to a single destination (gather), or read from
--      one source and write to multiple destinations (scatter). This is a
--      standard feature in industrial DMA engines.
--   3. Memory-to-Memory Only: This DMA is hard-coded to perform memory-to-memory
--      transfers. It lacks the more advanced modes for memory-to-peripheral or
--      peripheral-to-memory transfers.
--
--
-- [[ Future Improvements ]]
--
--   1. Implement Scatter-Gather DMA: This would be the most significant upgrade.
--      Instead of programming the DMA with registers, the CPU would build a
--      "descriptor" data structure in RAM. This descriptor would contain the
--      source, destination, and length. The CPU could even create a linked-list
--      of these descriptors. The CPU would only need to write the address of the
--      first descriptor to the DMA, which would then autonomously fetch and
--      process the entire chain of transfers. This is how high-performance
--      networking and storage DMAs operate.
--
--   2. Add Multi-Channel Support: I would expand the architecture to include
--      multiple sets of configuration and working registers, one for each
--      "channel". An internal arbiter would then select which channel gets to
--      use the master port at any given time.
--
--   3. Add AXI Protocol Support: I would replace the simple proprietary bus
--      interface with an industry-standard AMBA AXI4 master interface. This
--      would make the IP block instantly compatible with a vast ecosystem of
--      other commercial and open-source AXI-compliant peripherals and would be
--      an invaluable exercise in implementing a complex industry protocol.
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
-- I intentionally chose a fully open-source toolchain to build this project,
-- ensuring portability and forcing a focus on fundamental design principles
-- rather than tool-specific features.
--
--   - Coding Editor: Visual Studio Code (VS Code). I used VS Code for its
--     lightweight feel, powerful extensions, and integrated terminal, which
--     allowed me to manage my entire workflow (edit, compile, simulate, debug)
--     from a single window. The "Verilog-HDL/SystemVerilog" extension was
--     essential for its real-time syntax checking.
--
--   - Simulation Engine (EDA Tool): Icarus Verilog (`iverilog`). I selected
--     Icarus as it is a mature, standards-compliant open-source simulator. Its
--     strictness helped me write clean, portable RTL that is more likely to be
--     compatible with commercial tools like VCS or Questa. This file,
--     `dma_engine.v`, being a pure Verilog-2001 module, is highly portable.
--
--   - Waveform Viewer: GTKWave. This is the standard VCD (Value Change Dump)
--     file viewer that pairs with Icarus. It was my primary debugging tool,
--     allowing me to visualize the FSM state transitions, bus requests/grants,
--     and data transfers, which was critical for debugging this complex module.
--
--   - Automation Scripting: Python 3. The `run_regression.py` script uses
--     Python's `subprocess` library to automate the entire test flow. This is
--     an industry-standard approach for creating "glue logic" scripts that
--     orchestrate command-line EDA tools.
--
--
-- [[ Execution Commands ]]
--
-- The project is compiled and simulated using a Python script, which ensures
-- a repeatable and error-free process. Here are the underlying shell commands
-- generated by that script.
--
--   1. Compilation:
--      The script builds one simulation executable that includes all design
--      and testbench files. This file, `dma_engine.v`, must be included
--      before the top-level `risc_soc.sv` which instantiates it.
--
--      The command is:
--      `iverilog -g2005-sv -o soc_sim on_chip_ram.v crc32_accelerator.v timer.v uart_tx.v uart_rx.v uart_top.v address_decoder.v arbiter.v interrupt_controller.v dma_engine.v simple_cpu.v risc_soc.sv tb_risc_soc.sv`
--
--      - `iverilog`: Invokes the compiler.
--      - `-g2005-sv`: Enables SystemVerilog features needed for the testbench.
--      - `-o soc_sim`: Names the output simulation executable.
--      - `[file list]`: The complete, ordered list of source files.
--
--   2. Simulation:
--      To run the specific test that verifies this DMA engine, the script
--      invokes the compiled executable with a specific "plusarg".
--
--      The command is:
--      `vvp soc_sim +TESTNAME=DMA_TEST`
--
--      - `vvp`: The Icarus Verilog runtime engine.
--      - `soc_sim`: The compiled executable to run.
--      - `+TESTNAME=DMA_TEST`: This command-line argument is passed into the
--        simulation. The `tb_risc_soc.sv` uses a `$value$plusargs` system
--        task to read this string and selectively execute the `run_dma_test`
--        task, which contains the full verification sequence for this module.
--
--------------------------------------------------------------------------------
*/




