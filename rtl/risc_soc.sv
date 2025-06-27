// Copyright (c) 2025 Kumar Vedang
// SPDX-License-Identifier: MIT
//
// This source file is part of the RISC-V SoC project.
//

/*
--------------------------------------------------------------------------------
-- Module Name: risc_soc
-- Project: A Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: Kumar Vedang
--------------------------------------------------------------------------------
--
-- High-Level Module Purpose:
-- This module, `risc_soc`, is the top-level entity of the entire System-on-Chip.
-- It acts as the "system integrator" or the main "schematic" where all the
-- individual IP blocks (the CPU, DMA, RAM, peripherals, etc.) that were
-- designed and unit-tested separately are brought together and "wired" up.
-- This file does not contain much complex behavioral logic itself; instead, its
-- primary role is structural--to define the system's architecture by connecting
-- all the components.
--
-- Architectural Overview:
-- The architecture implemented here is a memory-mapped, multi-master system.
--   - Two bus masters (the `simple_cpu` and `dma_engine`) can initiate bus
--     transactions.
--   - A suite of slave peripherals (`on_chip_ram`, `crc32_accelerator`, etc.)
--     respond to these transactions.
--   - A central "interconnect" logic, consisting of an `arbiter` and an
--     `address_decoder`, manages the entire system.
--
-- Communication Flow:
-- This module defines the physical pathways (the `wires`) for communication.
-- When a master requests the bus, the `arbiter` grants access. The logic in
-- this file then multiplexes that master's signals onto the main system bus.
-- The `address_decoder` determines which slave is being targeted, and the
-- appropriate chip select is asserted. Data flows from the master to the slave
-- on a write cycle, or from the selected slave back to all masters on a read
-- cycle. This file is the physical realization of that entire data flow.
--
--------------------------------------------------------------------------------
*/


`timescale 1ns / 1ps


// This `module` declaration defines the boundary of the entire System-on-Chip.
// The name `risc_soc` reflects its function. The port list in the parentheses
// defines the highest-level I/O pins that would connect to the outside world
// (or the testbench in our case). All other components are instantiated and
// encapsulated within this module.

module risc_soc (

     // --- System-Wide I/O Ports ---
    // These are the primary pins connecting the SoC to the external world.

    // `clk`: A 1-bit input defining the global system clock. This signal is
    // routed to every single sub-module to drive all synchronous logic.
    input clk,

    // `rst_n`: A 1-bit input for the active-low global reset. This is also
    // routed to every sub-module to ensure the entire system starts in a
    // known, predictable state.
    input rst_n,

    // `bfm_mode`: A 1-bit input used for verification purposes. When high, it
    // puts the CPU into a special mode where the testbench can directly drive
    // the CPU's bus signals, bypassing its fetch/decode logic. This enables
    // powerful, deterministic testing. This pin would be tied to '0' in a
    // real hardware implementation.
    input bfm_mode,

    // `uart_tx_pin`: A 1-bit output carrying the serial data transmitted by the
    // UART peripheral. This would connect to the RX pin of an external device.
    output uart_tx_pin,

    // `uart_rx_pin`: A 1-bit input to receive serial data from an external
    // device, which is then fed into the UART peripheral.
    input uart_rx_pin
    );
    
    // --- CPU Master Bus Wires ---
    // These wires represent the bus interface originating from the CPU (`u_cpu`).
    // They serve as inputs to the system's interconnect logic (arbiter/muxes).

    wire cpu_m_req; // Signal from CPU to Arbiter, requesting bus access.

    wire cpu_m_gnt; // Signal from Arbiter to CPU, granting bus access.

    wire [31:0] cpu_m_addr; // The address bus driven by the CPU. 
    wire [31:0] cpu_m_wdata; // The write-data bus driven by the CPU.
    wire [31:0] cpu_m_rdata; // The read-data bus that feeds data back *to* the CPU.

    wire cpu_m_wr_en; // The write-enable signal driven by the CPU.

    // --- DMA Master Bus Wires ---
    // These wires represent the bus interface originating from the DMA engine (`u_dma`).
    // They are parallel to the CPU's bus and also serve as inputs to the interconnect.

    wire dma_m_req; // Signal from DMA to Arbiter, requesting bus access.
    wire dma_m_gnt;  // Signal from Arbiter to DMA, granting bus access.

    wire [31:0] dma_m_addr; // The address bus driven by the DMA when it is the master.
    wire [31:0] dma_m_wdata;  // The write-data bus driven by the DMA.
    wire [31:0] dma_m_rdata; // The read-data bus that feeds data back *to* the DMA.

    wire dma_m_wr_en; // The write-enable signal driven by the DMA.

    // --- Unified System Bus Wires ---
    // These wires represent the main, shared system bus. Their values are determined
    // by the interconnect logic, which selects one of the master buses to drive them.

    wire [31:0] bus_addr; // The address bus seen by all slave peripherals.
    wire [31:0] bus_wdata; // The write-data bus seen by all slave peripherals.
    wire [31:0] bus_rdata;  // The read-data bus driven by the selected slave.

    wire bus_wr_en;  // The write-enable signal seen by all slave peripherals.

    // --- Slave Chip Select Wires ---
    // Each wire here is a unique chip-select signal. They are driven by the
    // `address_decoder` and connect to the `cs_n` port of a specific slave.
    // Only one of these should be active (low) at any given time.

    wire ram_cs_n;  // Chip select for the On-Chip RAM (`u_ram`).
    wire dma_s_cs_n;  // Chip select for the DMA's *slave* port (`u_dma`).
    wire crc_cs_n; // Chip select for the CRC Accelerator (`u_crc`).
    wire intc_cs_n; // Chip select for the Interrupt Controller (`u_intc`).
    wire timer_cs_n; // Chip select for the Timer (`u_timer`).
    wire uart_cs_n;  // Chip select for the UART (`u_uart`).


    // --- Slave Read Data Wires ---
    // Each slave has its own `rdata` output port. These wires capture those
    // individual outputs before they are multiplexed onto the main `bus_rdata`.

    wire [31:0] ram_rdata; // Read data coming from the On-Chip RAM. 
    wire [31:0] dma_s_rdata; // Read data from the DMA's slave status registers.
    wire [31:0] crc_rdata; // Read data from the CRC Accelerator.
    wire [31:0] intc_rdata; // Read data from the Interrupt Controller's status registers.
    wire [31:0] timer_rdata; // Read data from the Timer.
    wire [31:0] uart_rdata; // Read data from the UART's status/data registers.


    // --- Interrupt Wires ---
    // These wires form the interrupt signaling chain within the SoC.

    wire dma_done_irq; // Raw interrupt signal from the DMA engine.
    wire timer_irq_out; // Raw interrupt signal from the Timer.
    wire uart_irq_out; // Raw interrupt signal from the UART.
    wire cpu_irq_in; // The final, combined interrupt signal fed *to* the CPU.


    // --- Master-to-Bus Multiplexers ---
    // This block of logic uses `assign` statements with ternary operators to create
    // a set of 2-to-1 multiplexers. The purpose is to select which master's bus
    // signals (CPU or DMA) are routed to the main, shared system bus. The select
    // line for these multiplexers is the `dma_m_gnt` signal from the arbiter.
    // Since the CPU has higher priority, if the DMA is not granted the bus, the
    // CPU is assumed to be the default master.

    // This assignment creates the multiplexer for the main system address bus.
    // If `dma_m_gnt` is high (DMA has control), `bus_addr` takes the value of `dma_m_addr`.
    // Otherwise, `bus_addr` takes the value of the default master, `cpu_m_addr`.
    assign bus_addr = dma_m_gnt ? dma_m_addr : cpu_m_addr;

    // This creates the multiplexer for the main system write-enable signal.
    // If `dma_m_gnt` is high, `bus_wr_en` is driven by the DMA's write-enable.
    // Otherwise, it is driven by the CPU's write-enable.
    assign bus_wr_en = dma_m_gnt ? dma_m_wr_en : cpu_m_wr_en;


    // This creates the multiplexer for the 32-bit system write-data bus.
    // If `dma_m_gnt` is high, `bus_wdata` carries data from the DMA.
    // Otherwise, it carries data from the CPU.
    assign bus_wdata = dma_m_gnt ? dma_m_wdata : cpu_m_wdata;


    // --- Slave-to-Bus Read Data Multiplexer ---
    // This `assign` statement implements a large priority-encoded multiplexer
    // for the read data path. Its purpose is to select which of the many slave
    // `rdata` outputs gets to drive the main `bus_rdata`. The selection is based
    // on which slave's chip select (`cs_n`) is active (low).
    // The nested ternary operators create a priority chain: `ram_cs_n` is checked
    // first, then `dma_s_cs_n`, and so on. This is safe because the `address_decoder`
    // is designed to only assert one `cs_n` at a time.
    assign bus_rdata = !ram_cs_n ? ram_rdata : // If RAM is selected, route its data.
                       !dma_s_cs_n ? dma_s_rdata :  // Else, if DMA slave port is selected...
                       !crc_cs_n ? crc_rdata :  // Else, if CRC is selected...
                       !timer_cs_n ? timer_rdata : // Else, if Timer is selected...
                       !intc_cs_n ? intc_rdata : // Else, if Interrupt Controller is selected...
                       !uart_cs_n ? uart_rdata : // Else, if UART is selected...
                       32'hBAD_DDAA; // Default case: If no slave is selected, drive a recognizable
                                                      // garbage value. This is extremely useful for debugging, as
                                                      // seeing `BAD_DDAA` on the bus indicates a read from an invalid
                                                      // or unmapped memory address.



    // --- Bus-to-Master Read Data Fanout ---
    // These assignments distribute the final, multiplexed read data from the
    // main system bus back to *both* masters simultaneously.

    // The CPU's read data port is continuously connected to the main bus's read data.
    assign cpu_m_rdata = bus_rdata;

    // The DMA's read data port is also continuously connected.
    // Each master is responsible for knowing *when* to latch this data based on its
    // own FSM and bus grant signal.
    assign dma_m_rdata = bus_rdata;

    // --- Master Instantiation: The CPU ---
    // This instantiates the `simple_cpu` module, which is the primary brain and
    // high-priority master of the SoC. The port connections (`.port(wire)`)
    // wire it into the system's control and data fabric.
    //   - `.clk, .rst_n`: Connected to the global system clock and reset.
    //   - `.irq_in`: Receives the final, unified interrupt signal from the `u_intc`.
    //   - `.bfm_mode`: Exposes the verification-only BFM mode to the top level.
    //   - `.m_req, .m_gnt`: Connects the CPU's request/grant handshake to the `u_arbiter`.
    //   - `.m_addr, .m_wdata, .m_wr_en`: The CPU's master bus ports are connected to
    //     the `cpu_m_*` wires, feeding into the bus multiplexers.
    //   - `.m_rdata`: The CPU's read port is connected to its dedicated read data wire.
    simple_cpu u_cpu (
        .clk(clk), 
        .rst_n(rst_n), 
        .irq_in(cpu_irq_in), 
        .bfm_mode(bfm_mode), 
        .m_req(cpu_m_req), 
        .m_gnt(cpu_m_gnt), 
        .m_addr(cpu_m_addr), 
        .m_wr_en(cpu_m_wr_en), 
        .m_wdata(cpu_m_wdata), 
        .m_rdata(cpu_m_rdata) 
    );



    // --- Master/Slave Instantiation: The DMA Engine ---
    // This instantiates the `dma_engine`, a powerful peripheral with a dual
    // personality. It acts as both a bus slave (for configuration) and a bus
    // master (for data transfers).
    //   - Slave Port (`s_`):
    //     - `.s_cs_n`: Connected to its dedicated chip select from the `u_addr_decoder`.
    //     - `.s_wr_en, .s_addr, .s_wdata`: Connected to the main system bus for configuration.
    //     - `.s_rdata`: Drives its status information onto its dedicated read data wire.
    //   - Master Port (`m_`):
    //     - `.m_req, .m_gnt`: Connects to the low-priority port of the `u_arbiter`.
    //     - `.m_addr, .m_wdata, .m_wr_en`: Feeds the bus multiplexers.
    //     - `.m_rdata`: Receives read data from the main bus.
    //   - `.dma_done`: The output interrupt signal is wired to the `u_intc`.
    dma_engine u_dma ( 
        .clk(clk), 
        .rst_n(rst_n), 
        .s_cs_n(dma_s_cs_n), 
        .s_wr_en(bus_wr_en), 
        .s_addr(bus_addr[4:2]), 
        .s_wdata(bus_wdata), 
        .s_rdata(dma_s_rdata), 
        .m_req(dma_m_req), 
        .m_gnt(dma_m_gnt), 
        .m_addr(dma_m_addr), 
        .m_wr_en(dma_m_wr_en), 
        .m_wdata(dma_m_wdata), 
        .m_rdata(dma_m_rdata), 
        .dma_done(dma_done_irq) 
    );


    // --- Slave Instantiation: CRC Accelerator ---
    // This instantiates the `crc32_accelerator`, a simple hardware offload engine.
    // It is a pure slave device.
    //   - `.cs_n`: Connected to its chip select from the `u_addr_decoder`.
    //   - `.wr_en, .addr, .wdata`: Connected to the main bus to receive commands/data.
    //   - `.rdata`: Drives its calculated result onto its dedicated read data wire.
    crc32_accelerator u_crc (
        .clk(clk),
        .rst_n(rst_n),
        .cs_n(crc_cs_n),
        .wr_en(bus_wr_en),
        .addr(bus_addr[3:2]),
        .wdata(bus_wdata),
        .rdata(crc_rdata)
    );


    // --- Slave Instantiation: On-Chip RAM ---
    // This instantiates the `on_chip_ram`, which serves as the main system memory
    // for both CPU instructions and data.
    //   - `.cs_n`: Connected to its chip select from the `u_addr_decoder`.
    //   - `.wr_en, .addr, .wdata`: Connected to the main bus. Note that only the lower
    //     16 bits of the address bus are used, corresponding to a 64KB memory size.
    //   - `.rdata`: Drives the stored memory data onto its dedicated read data wire.
    on_chip_ram u_ram ( 
        .clk(clk), 
        .cs_n(ram_cs_n), 
        .wr_en(bus_wr_en), 
        .addr(bus_addr[15:0]), 
        .wdata(bus_wdata), 
        .rdata(ram_rdata) 
    );
    




    /*
    ----------------------------------------------------------------------------
    -- Concept Deep Dive: Bus Arbitration
    ----------------------------------------------------------------------------
    -- What is it?
    -- Bus Arbitration is the process of deciding which "master" device (like a
    -- CPU or DMA) gets exclusive control of the shared system bus when multiple
    -- masters request it at the same time. It's like a traffic cop for data.
    --
    -- Where is it used in this file?
    -- It is used right here to manage our two bus masters: `u_cpu` and `u_dma`.
    -- Both masters can assert their request lines (`cpu_m_req`, `dma_m_req`).
    -- The `u_arbiter` module takes these requests and decides which one to
    -- grant by asserting either `cpu_m_gnt` or `dma_m_gnt`.
    --
    -- Why is it used?
    -- Without arbitration, both the CPU and DMA could try to drive their own
    -- address and data onto the shared bus simultaneously. This would cause
    -- "bus contention," leading to electrical conflicts, corrupted data, and
    -- unknown ('X') values propagating through the system. This arbiter
    -- implements a "Fixed-Priority" scheme: the CPU (connected to req_0) has
    -- higher priority than the DMA (req_1). If both request the bus at the
    -- same time, the CPU will always be granted access, ensuring that critical
    -- control tasks are never starved by background data transfers. The grant
    -- signals from the arbiter are the key control signals for the bus
    -- multiplexers defined above.
    ----------------------------------------------------------------------------
    */


    // --- Interconnect Instantiation: The Arbiter ---
    // This instantiates the `arbiter`, the core logic block for managing bus access
    // in this multi-master system.
    //   - `.req_0`: Connected to the CPU's request line (`cpu_m_req`).
    //   - `.req_1`: Connected to the DMA's request line (`dma_m_req`).
    //   - `.gnt_0`: Drives the CPU's grant line (`cpu_m_gnt`).
    //   - `.gnt_1`: Drives the DMA's grant line (`dma_m_gnt`), which also serves as the
    //     select signal for the master bus multiplexers.


    arbiter u_arbiter( 
        .clk(clk), 
        .rst_n(rst_n), 
        .req_0(cpu_m_req), 
        .req_1(dma_m_req), 
        .gnt_0(cpu_m_gnt), 
        .gnt_1(dma_m_gnt) 
    );

    // --- Slave Instantiation: The Timer ---
    // This instantiates the general-purpose `timer` peripheral.
    //   - `.cs_n`: Connected to its chip select from the `u_addr_decoder`.
    //   - `.irq_out`: Drives its raw interrupt signal to the `u_intc`.
    timer u_timer ( 
        .clk(clk), 
        .rst_n(rst_n), 
        .cs_n(timer_cs_n), 
        .wr_en(bus_wr_en), 
        .addr(bus_addr[3:0]), 
        .wdata(bus_wdata), 
        .rdata(timer_rdata), 
        .irq_out(timer_irq_out) 
    );


    // --- Slave Instantiation: The Interrupt Controller ---
    // This instantiates the `interrupt_controller`, which aggregates interrupts
    // from various sources and presents a single interrupt line to the CPU.
    //   - `.irq0_in, .irq1_in, .irq2_in`: Receive raw interrupt signals from the
    //     DMA, Timer, and UART respectively.
    //   - `.irq_out`: Drives the final, unified interrupt signal to the CPU (`cpu_irq_in`).
    interrupt_controller u_intc ( 
        .clk(clk), 
        .rst_n(rst_n), 
        .irq0_in(dma_done_irq), 
        .irq1_in(timer_irq_out), 
        .irq2_in(uart_irq_out), 
        .cs_n(intc_cs_n), 
        .wr_en(bus_wr_en), 
        .addr(bus_addr[3:0]), 
        .rdata(intc_rdata), 
        .irq_out(cpu_irq_in) 
    );






    /*
    ----------------------------------------------------------------------------
    -- Concept Deep Dive: Memory-Mapped I/O (MMIO)
    ----------------------------------------------------------------------------
    -- What is it?
    -- Memory-Mapped I/O is a fundamental system architecture where peripherals
    -- (like the UART, Timer, or DMA configuration registers) are assigned unique
    -- addresses and are accessed using the same instructions that are used to
    -- access memory (e.g., Load Word, Store Word).
    --
    -- Where is it used in this file?
    -- The entire SoC is built on this principle. The `u_addr_decoder` module
    -- is the physical hardware that implements the MMIO scheme. It constantly
    -- monitors the main `bus_addr` and, based on the high-order bits, asserts
    -- a single, unique, active-low chip select line (`_cs_n`) for the targeted
    -- peripheral, according to the system's memory map specification.
    --
    -- Why is it used?
    -- MMIO greatly simplifies both the hardware and software design.
    --   - For Hardware: It creates a standardized slave interface. All
    --     peripherals can be designed to respond to the same simple set of
    --     bus signals (`cs_n`, `wr_en`, `addr`, etc.).
    --   - For Software: It eliminates the need for special I/O instructions.
    --     A C-compiler can simply use pointers to interact with hardware
    --     registers, making device driver development intuitive and efficient.
    -- The `address_decoder` is the gatekeeper that makes this entire elegant
    -- abstraction work, ensuring only one device talks on the bus at a time.
    ----------------------------------------------------------------------------
    */


    // --- Interconnect Instantiation: The Address Decoder ---
    // This instantiates the `address_decoder`, the hardware that implements the
    // system's memory map.
    //   - `.addr`: Takes the unified `bus_addr` as its input.
    //   - `.*_cs_n`: Drives the individual chip select lines for every slave
    //     peripheral in the system based on the input address.
    address_decoder u_addr_decoder ( 
        .addr(bus_addr), 
        .ram_cs_n(ram_cs_n), 
        .dma_cs_n(dma_s_cs_n), 
        .crc_cs_n(crc_cs_n), 
        .intc_cs_n(intc_cs_n), 
        .timer_cs_n(timer_cs_n), 
        .uart_cs_n(uart_cs_n)
    );
    

    // --- Slave Instantiation: The UART ---
    // This instantiates the `uart_top` module, which handles serial communication.
    //   - `.tx_pin, .rx_pin`: Connects directly to the top-level I/O pins of the SoC.
    //   - `.irq_out`: Drives its interrupt signal to the `u_intc`.
    uart_top u_uart (
        .clk (clk),
        .rst_n (rst_n),
        .cs_n (uart_cs_n),
        .wr_en (bus_wr_en),
        .addr (bus_addr[3:0]),
        .wdata (bus_wdata),
        .rdata (uart_rdata),
        .tx_pin (uart_tx_pin),
        .rx_pin (uart_rx_pin),
        .irq_out (uart_irq_out)
    );
endmodule




/*
--------------------------------------------------------------------------------
--                              PROJECT ANALYSIS
--------------------------------------------------------------------------------
--
-- 
--
-- ############################################################################
-- ##                 Development Chronicle and Methodology                  ##
-- ############################################################################
--
--
-- [[ Relevance of This File ]]
--
-- This file, `risc_soc.sv`, is arguably the single most important file in the
-- entire project. While other modules contain complex behavioral logic, this
-- file defines the system's soul: its architecture. It's the blueprint that
-- shows how every independently designed IP block is instantiated and connected
-- to form a single, cohesive, and functional System-on-Chip. It physically
-- implements the high-level block diagram, making it the source of truth for
-- how the entire system is structured. Understanding this file is key to
-- understanding the project as a whole.
--
--
-- [[ Key Concepts Implemented ]]
--
-- This file is a practical demonstration of several critical, high-level VLSI concepts:
--
--   1. Hierarchical Design: This file sits at the top of the design hierarchy,
--      instantiating other modules as "black boxes." This is the core principle
--      of managing complexity in large-scale chip design.
--
--   2. System Integration: The primary task of this file is to perform system
--      integration by wiring together all the pre-verified sub-modules. It's a
--      masterclass in connecting master ports, slave ports, and global signals.
--
--   3. Bus Architecture: It physically creates the shared bus fabric. The `assign`
--      statements for `bus_addr`, `bus_wdata`, and `bus_rdata` are not just
--      logic; they are the hardware implementation of the system's data highways
--      and the multiplexing that controls traffic on them.
--
--   4. Multi-Master System Design: By instantiating two masters (`u_cpu`, `u_dma`)
--      and the `u_arbiter` that manages them, this file creates the fundamental
--      structure for a high-performance system capable of parallel operations.
--
--
-- [[ My Coding Ethic and Implementation Flow ]]
--
-- Creating this top-level file was the final step in the hardware design phase,
-- and I approached it with a methodical, incremental process to avoid a
-- debugging nightmare.
--
--   - Prerequisite: I did not start this file until every single sub-module
--     (CPU, DMA, RAM, peripherals, arbiter, decoder) had passed its own
--     dedicated unit test. This was a non-negotiable rule in my workflow.
--
--   - Initial Outline (Pen and Paper): I started by drawing the final block
--     diagram on paper, explicitly drawing every wire that needed to be declared
--     in this file. This included the master buses, the unified bus, the
--     individual chip selects, and the interrupt lines.
--
--   - Incremental Instantiation: I wrote the Verilog by instantiating components
--     in a logical order, from simplest to most complex.
--       1. I first instantiated all the slave peripherals and the interconnect
--          logic (`u_arbiter` and `u_addr_decoder`).
--       2. I declared all the necessary wires and connected these slaves and
--          interconnect blocks.
--       3. Only then did I instantiate the bus masters (`u_cpu` and `u_dma`) and
--          connect their master ports to the now-existing interconnect wires.
--
--   - Naming Consistency: I followed a strict naming convention to maintain
--     clarity. For example, wires connecting to the CPU's master port were
--     prefixed with `cpu_m_`, slave ports with `s_`, and the unified bus with
--     `bus_`. This made the code much easier to read and debug, as the purpose
--     of each wire was evident from its name.
--
--   - Progressive Verification: As I will detail later, I did not wait until
--     everything was connected to start testing. I brought the system up
--     incrementally, first testing the CPU-to-RAM path, then CPU-to-peripheral,
--     before ever attempting a complex DMA test. This allowed me to isolate
--     integration bugs to a smaller set of connections.
--
--------------------------------------------------------------------------------
*/



/*
--
-- ############################################################################
-- ##                   Verification and Debugging Chronicle                 ##
-- ############################################################################
--
--
-- [[ Verification Strategy for the Integrated SoC ]]
--
-- Verifying this top-level design is the most complex verification task in the
-- project. It's not enough to know that the individual components work; we must
-- prove that they work together correctly through the shared interconnect. My
-- strategy was based on a full system-level testbench, `tb_risc_soc.sv`, which
-- verifies end-to-end scenarios.
--
--   - BFM-Driven Testing: The testbench uses a Bus Functional Model (BFM) to
--     drive the CPU's bus interface. This is a powerful technique that allows
--     the testbench to directly issue bus reads and writes, acting like a
--     perfect, deterministic CPU. This gives me precise control to create
--     very specific test scenarios that would be difficult to set up by writing,
--     compiling, and loading a real RISC-V program.
--
--   - End-to-End Scenarios: The tests are not simple register checks. They
--     verify complete data flows. For example, the `DMA_TEST` is the ultimate
--     system test:
--       1. The BFM (acting as the CPU) writes to the DMA's slave registers.
--       2. The DMA then becomes a master, requests the bus from the arbiter.
--       3. The DMA performs reads from the RAM.
--       4. The DMA performs writes back to the RAM.
--       5. The DMA asserts an interrupt, which is routed through the interrupt
--          controller back to the BFM.
--     A single test like this stresses nearly every single wire and module
--     instantiated in this file.
--
--   - Automated Regression: All these system-level tests are managed by the
--     `run_regression.py` script. This ensures that after I fix a bug or add a
--     feature, I can quickly run the entire suite of tests to guarantee I haven't
--     broken any existing functionality (a "regression"). The final "PASS"
--     report from this script is the ultimate sign-off for the SoC design.
--
--
-- [[ A Challenging Integration Bug and Debugging Story ]]
--
-- Bug Symptom: During the early stages of integration, the very first test—a
-- simple CPU write to RAM followed by a read—was failing. The scoreboard
-- reported a data mismatch. For example, I would write `0x12345678` to an
-- address, but the read-back value was `0x00000000`. This was confusing because
-- both the CPU and RAM had passed their unit tests flawlessly.
--
-- My Debugging Process:
--
--   1. Hypothesis: Since the read-back value was all zeros and not a random
--      or 'X' value, my initial hypothesis was that the write operation was
--      failing to happen at all. I suspected a problem in the bus control
--      logic. Specifically: "The `bus_wr_en` signal is not being correctly
--      propagated from the master to the RAM slave."
--
--   2. Evidence Gathering (Waveform Analysis): I opened GTKWave and loaded the
--      waveform from the failing test. I added a few key signals to trace the
--      write transaction from start to finish:
--      - `clk`, `rst_n`
--      - The CPU's master port: `cpu_m_addr`, `cpu_m_wdata`, `cpu_m_wr_en`.
--      - The unified system bus: `bus_addr`, `bus_wdata`, `bus_wr_en`.
--      - The RAM's inputs: `u_ram.addr`, `u_ram.wdata`, and most importantly, `u_ram.wr_en`.
--
--   3. The "Aha!" Moment: I zoomed in on the write cycle.
--      - I could see the CPU correctly driving `cpu_m_addr` and `cpu_m_wdata`.
--      - I also saw `cpu_m_wr_en` go high for one clock cycle. This was correct.
--      - I then looked at the unified `bus_wr_en` signal, which was fed by the
--        multiplexer logic defined in this file. It was also correctly going high.
--      - The breakthrough came when I looked at the input to the RAM itself. The
--        `u_ram.wr_en` pin was stuck at a constant '0'.
--
--      This was a classic integration bug. The `bus_wr_en` wire existed, but I had
--      made a typo in the instantiation of the `u_ram` module. Instead of connecting
--      the RAM's `wr_en` port to the `bus_wr_en` wire, I had mistakenly connected
--      it to a non-existent or incorrect wire.
--      Example of the buggy code: `on_chip_ram u_ram (..., .wr_en(write_en), ...)`
--      Instead of the correct: `on_chip_ram u_ram (..., .wr_en(bus_wr_en), ...)`
--
-- The Fix: The fix was a simple one-line correction in this `risc_soc.sv` file,
-- changing the port connection for the `u_ram` instance to use the correct
-- `bus_wr_en` wire. This experience was a powerful lesson that even after
-- extensive unit testing, simple wiring and connection errors during top-level
-- integration are a common and critical source of bugs. It reinforced the need
-- for careful, methodical checking of all connections in the final design.
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
-- The architecture defined in this file is a direct, albeit simplified, model
-- of the vast majority of embedded systems, microcontrollers (MCUs), and IP
-- subsystems found in the digital VLSI industry. The role of an "SoC Integrator,"
-- whose job is to create a top-level file like this one, is a dedicated and
-- critical position in any large semiconductor company.
--
-- Practical examples include:
--
--   1. Embedded Microcontrollers (MCUs): A typical MCU from a company like
--      STMicroelectronics (STM32 series) or Microchip (PIC/AVR series) has
--      this exact architecture. They contain a processor core (like an ARM
--      Cortex-M), a DMA controller, on-chip RAM and Flash, and a suite of
--      peripherals (UART, I2C, SPI, Timers). The top-level design of such a
--      chip would look structurally identical to this file, connecting these
--      IP blocks to a central bus matrix (like an AMBA bus).
--
--   2. Subsystems within a Larger ASIC: In a massive chip like a smartphone
--      processor or a GPU, the design is broken down into major subsystems.
--      There might be a "Modem Subsystem," a "Display Subsystem," or a "Security
--      Enclave." Each of these subsystems often contains its own small, local
--      processor, its own DMA, and its own set of specialized peripherals. This
--      `risc_soc` is a perfect model for one of these self-contained subsystems
--      that would be delivered as a single IP block to the team integrating the
--      full chip.
--
--   3. FPGA Designs: In the FPGA world, designers often build systems by
--      instantiating a soft-processor core (like a MicroBlaze or Nios II),
--      a DMA controller from the vendor's IP library, and custom Verilog
--      peripherals. The top-level file in such a design serves the exact same
--      purpose as this one: wiring together vendor IP and custom IP to create
--      a complete, programmable system.
--
--
-- [[ Industrially Relevant Insights Gained ]]
--
-- Working on this file was a masterclass in system-level thinking and provided
-- several insights that are directly relevant to a professional VLSI role:
--
--   - Technical Insight: The "Protocol is King." My biggest takeaway is that
--     the entire system's stability relies on every single component rigorously
--     adhering to the defined bus protocol. One misbehaving master that doesn't
--     de-assert its request, or one slave that doesn't tri-state its output
--     correctly, can bring down the entire system. In industry, this means that
--     the specification for the interconnect (like AXI or APB) is the most
--     important document, and compliance is non-negotiable.
--
--   - Methodological Insight: "Integrate Early, Integrate Often" is not just a
--     software term. The process of creating this file taught me the immense
--     value of an incremental integration strategy. Trying to connect all 10+
--     modules at once and then debugging would have been impossible. By bringing
--     the system up piece by piece (CPU-to-RAM, then CPU-to-Timer, etc.), I was
--     able to debug a much smaller part of the system at each step. This is a
--     critical project management and risk-reduction strategy.
--
--   - Non-Technical Insight: The Importance of Clear Boundaries and Ownership.
--     This file is where the work of many different teams would meet. One team
--     delivers the CPU, another the DMA, another the peripherals. The job of the
--     SoC integrator, who works on this file, relies entirely on the other teams
--     delivering well-documented, verified, and protocol-compliant IP. It
--     highlighted the importance of clear communication, good documentation,
--     and trust between different engineering groups in a large project.
--
--
-- [[ Current Limitations and Future Improvements ]]
--
-- The architecture in this file, while functional, has limitations that would
-- be addressed in a commercial design:
--
--   - Limitation: The simple, shared bus is a performance bottleneck. If the
--     DMA is performing a high-speed transfer, the CPU is completely blocked
--     from accessing any other peripheral, even if that peripheral is idle.
--
--   - Future Improvement: I would upgrade the interconnect to a more advanced,
--     industry-standard architecture like AMBA AXI4. An AXI interconnect has
--     separate channels for read addresses, read data, write addresses, and
--     write data, allowing for multiple outstanding transactions and much
--     higher parallelism. This would replace the simple `assign`-based bus
--     logic with a much more complex but powerful `AXI_Interconnect` module.
--
--   - Limitation: There is no clock or power management. The entire SoC runs
--     on a single clock domain and has no concept of power-gating idle modules.
--
--   - Future Improvement: I would introduce clock-gating logic for each
--     peripheral. I would also design a "Power Management Unit" (PMU) as
--     another slave on the bus, which the CPU could program to turn off power
--     to entire sections of the chip when they are not in use, a critical
--     feature for any battery-powered device.
--
--------------------------------------------------------------------------------
*/



/*
-- 
--
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
-- automates the compilation and simulation steps. All commands are run from
-- the root directory of the project. Here is a breakdown of the commands the
-- script generates and executes in the terminal:
--
--   1. Compilation:
--      The script first constructs a single compilation command to build the
--      simulation executable. The order of files is critical to satisfy
--      dependencies. This `risc_soc.sv` file is the structural top-level that
--      includes all other RTL files.
--
--      The command is:
--      `iverilog -g2005-sv -o soc_sim rtl/*.v rtl/*.sv tb/tb_risc_soc.sv`
--
--      - `iverilog`: Invokes the Icarus Verilog compiler.
--      - `-g2005-sv`: A flag that tells the compiler to enable SystemVerilog
--        features, which are used heavily in the testbench (`tb_risc_soc.sv`).
--      - `-o soc_sim`: Specifies the name of the compiled output executable (`soc_sim`).
--      - `rtl/*.v rtl/*.sv`: A wildcard pattern to include all Verilog and
--        SystemVerilog design files from the `rtl` directory.
--      - `tb/tb_risc_soc.sv`: The top-level testbench file that instantiates this
--        `risc_soc` module as the DUT (Device Under Test).
--
--   2. Simulation:
--      After successful compilation, the script runs the simulation multiple times,
--      once for each test case in its list. For example, to run the `DMA_TEST`:
--
--      The command is:
--      `vvp soc_sim +TESTNAME=DMA_TEST > dma_test.log`
--
--      - `vvp`: The Verilog Virtual Processor, which is the runtime engine that
--        executes the compiled `soc_sim` file.
--      - `+TESTNAME=DMA_TEST`: This is a "plusarg," a standard way to pass
--        parameters from the command line into a simulation. The `tb_risc_soc.sv`
--        file contains a `$value$plusargs` system task that reads this string and
--        uses it to select which test sequence to run.
--      - `> dma_test.log`: This shell redirection pipes all the standard output
--        (like `$display` messages) from the simulation into a log file, which
--        the Python script can then open and parse to check for the "PASS" signature.
--
--   3. Running the Full Regression:
--      To run the entire suite of tests, the single command I execute is:
--
--      `python run_regression.py`
--
--      This one command triggers the entire compile-run-check flow for all tests,
--      providing a final, clean summary report in the terminal.
--
--------------------------------------------------------------------------------
*/








