// Copyright (c) 2025 Kumar Vedang
// SPDX-License-Identifier: MIT
//
// This source file is part of the RISC-V SoC project.
//


/*
--------------------------------------------------------------------------------
-- Module Name: uart_top
-- Project: A Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: Kumar Vedang
--------------------------------------------------------------------------------
--
-- High-Level Module Purpose:
-- This module, `uart_top`, is a structural wrapper. It does not contain any
-- complex FSMs or data processing logic itself. Instead, its sole purpose is
-- to instantiate and manage the `uart_tx` (transmitter) and `uart_rx`
-- (receiver) sub-modules, presenting them to the main SoC as a single, unified
-- UART peripheral.
--
-- Significance in the SoC Architecture:
-- This module demonstrates the principle of hierarchical design. By creating
-- this wrapper, we encapsulate the complexity of the transmitter and receiver.
-- The main `risc_soc` top-level file only needs to interact with this one
-- `uart_top` module, which makes the top-level design cleaner, more modular,
-- and easier to understand. This wrapper is responsible for routing bus
-- accesses from the CPU to the correct sub-module (TX or RX) based on the
-- address.
--
-- Communication and Integration:
-- This module acts as the single point of contact for the UART system.
--
--   - As a Bus Slave: It connects directly to the main system bus. It receives
--     bus transactions and, based on the address, internally decodes whether
--     the transaction is for the transmitter or the receiver.
--
--   - Managing Sub-Modules: It generates the appropriate chip select signals
--     for `uart_tx` and `uart_rx` and multiplexes their read data back onto
--     the shared system bus.
--
--   - Physical Interface: It routes the `tx_pin` from the transmitter and the
--     `rx_pin` to the receiver, connecting them to the top-level SoC pins. It
--     also passes the receiver's interrupt signal (`irq_out`) up to the main
--     system's interrupt controller.
--
--------------------------------------------------------------------------------
*/


`timescale 1ns / 1ps


// This `module` declaration defines the boundary of the `uart_top` wrapper.
// Its primary role is structural: to contain and connect the `uart_tx` and
// `uart_rx` sub-modules into a single cohesive peripheral.
module uart_top (

    // --- System Signals ---
    input clk,
    input rst_n,

    // --- Unified Slave Bus Interface ---
    // This is the single bus interface presented to the main SoC.

    // `cs_n`: The active-low chip select for the entire UART peripheral. Driven
    // by the top-level `address_decoder`.
    input cs_n,

    // `wr_en`: The write enable signal from the bus master (CPU).
    input wr_en,

    // `addr`: The 4-bit address bus from the CPU. This wrapper uses bit 2 of
    // this address to select between the TX and RX sub-modules.
    input [3:0]  addr,

    // `wdata`: The 32-bit write data bus from the CPU. 
    input [31:0] wdata,

    // `rdata`: The 32-bit read data bus to the CPU. This will be driven by
    // either the TX or RX sub-module, as selected by the internal logic.
    output [31:0] rdata,


    // --- UART Physical Pins and Interrupt Output ---

    // `tx_pin`: The final, single-bit serial transmit output pin for the SoC.
    output tx_pin,

    // `rx_pin`: The final, single-bit serial receive input pin for the SoC.
    input rx_pin,

    // `irq_out`: The combined interrupt output for the UART peripheral. In this
    // design, it is driven directly by the receiver's interrupt signal.
    output irq_out
    );

    // --- Internal Wires for Sub-Module Interconnection ---

    // `tx_rdata`: A wire to carry the read data (status) from the `uart_tx`
    // instance up to this module's read data multiplexer.
    wire [31:0] tx_rdata;

    // `rx_rdata`: A wire to carry the read data (received byte and status)
    // from the `uart_rx` instance up to the read data multiplexer.
    wire [31:0] rx_rdata;

    // `rx_irq`: A wire to carry the interrupt signal from the `uart_rx`
    // instance up to this module's `irq_out` port.
    wire rx_irq;

    // --- Internal Wires for Sub-Module Selection Logic ---


     // --- Internal Address Decoding Logic ---
    // This logic decodes the incoming 4-bit address (`addr`) to determine
    // which sub-module (TX or RX) the CPU is trying to access.

    // This `wire` will be high ('1') if address bit 2 is '0', selecting the transmitter.
    // The TX registers are mapped to addresses 0x...0 to 0x...3.

    // `sel_tx`: A combinational wire that goes high if the current bus access
    // is intended for the transmitter (i.e., address bit 2 is 0).
    wire sel_tx = (addr[2] == 1'b0);

    // This `wire` will be high ('1') if address bit 2 is '1', selecting the receiver.
    // The RX registers are mapped to addresses 0x...4 to 0x...7.

    // `sel_rx`: A combinational wire that goes high if the current bus access
    // is intended for the receiver (i.e., address bit 2 is 1).
    wire sel_rx = (addr[2] == 1'b1);



    // --- Sub-Module Chip Select Generation ---
    // This logic generates the individual chip selects for the sub-modules.

    // The chip select for the transmitter (`cs_tx_n`) is asserted ('0') only if the
    // main UART chip select (`cs_n`) is asserted AND `sel_tx` is true.


    // `cs_tx_n`: The generated chip select for the `uart_tx` instance. It is
    // asserted only if the main `cs_n` is active AND `sel_tx` is true.
    wire cs_tx_n = sel_tx ? cs_n : 1'b1;



    // The chip select for the receiver (`cs_rx_n`) is asserted only if the main
    // `cs_n` is asserted AND `sel_rx` is true.

    // `cs_rx_n`: The generated chip select for the `uart_rx` instance. It is
    // asserted only if the main `cs_n` is active AND `sel_rx` is true.                                                                                                                                                                                                         
    wire cs_rx_n = sel_rx ? cs_n : 1'b1;



    // --- Read Data Multiplexing ---
    // This `assign` statement acts as a 2-to-1 multiplexer for the read data path.
    // It selects the `rdata` source based on which sub-module is being accessed.
    // If `sel_tx` is true, it routes the read data from the transmitter (`tx_rdata`).
    // Otherwise, it routes the read data from the receiver (`rx_rdata`).
    assign rdata = sel_tx ? tx_rdata : rx_rdata;



    // --- Interrupt Pass-Through ---
    // This `assign` statement directly connects the interrupt signal coming from
    // the receiver sub-module (`rx_irq`) to the top-level interrupt output of
    // this wrapper module.
    assign irq_out = rx_irq;


    // --- Sub-Module Instantiation ---

    // This block instantiates the `uart_tx` module, giving it the instance
    // name `u_uart_tx`. It connects all the necessary ports.
    uart_tx u_uart_tx (
        .clk(clk), // Connect to the system clock

        .rst_n(rst_n),   // Connect to the system reset

        .cs_n(cs_tx_n),  // Connect to the generated chip select for the TX

        .wr_en(wr_en),  // Pass through the main write enable

        .addr(addr[1:0]),  // Pass through the lower 2 address bits for internal TX register selection

        .wdata(wdata), // Pass through the main write data bus

        .rdata(tx_rdata), // Connect to the internal wire for TX read data

        .tx_pin(tx_pin)  // Connect to the top-level transmit pin
    );

    // This block instantiates the `uart_rx` module, giving it the instance
    // name `u_uart_rx`. It connects all the necessary ports.
    uart_rx u_uart_rx (

        .clk(clk), // Connect to the system clock

        .rst_n(rst_n),  // Connect to the system reset

        .cs_n(cs_rx_n), // Connect to the generated chip select for the RX

        .wr_en(wr_en),  // Pass through the main write enable

        .addr(addr[1:0]), // Pass through the lower 2 address bits for internal RX register selection

        .wdata(wdata), // Pass through the main write data bus

        .rdata(rx_rdata), // Connect to the internal wire for RX read data

        .rx_pin(rx_pin), // Connect to the top-level receive pin

        .irq_out(rx_irq) // Connect to the internal wire for the RX interrupt
    );

endmodule




/*
--------------------------------------------------------------------------------
-- Conceptual Deep Dive: Hierarchical Design (The Wrapper/Facade Pattern)
--------------------------------------------------------------------------------
--
-- What is it?
-- Hierarchical design is a fundamental strategy for managing complexity in any
-- large engineering project, from software to digital hardware. Instead of
-- building a single, massive, monolithic design, the system is broken down
-- into smaller, more manageable, self-contained sub-components. A "wrapper"
-- (or "facade" in software terms) is a structural module whose job is to
-- assemble one or more of these sub-components and present them to the outside
-- world as a single, cohesive unit with a simplified interface.
--
-- Where is the concept used in this file?
-- This entire module, `uart_top`, is a perfect and explicit example of a
-- hardware wrapper.
--
--   - The Sub-Components: The actual logic for transmitting and receiving data
--     is contained in the `uart_tx` and `uart_rx` modules, respectively. These
--     are complex, stateful modules.
--
--   - The Wrapper: This `uart_top` module contains almost no complex logic.
--     Instead, it performs three key wrapper functions:
--       1. Instantiation: It creates instances of `uart_tx` and `uart_rx`.
--       2. Abstraction/Management: It hides the fact that there are two separate
--          sub-modules from the rest of the SoC. It takes the single UART chip
--          select and address bus and internally decodes which sub-module the
--          CPU is trying to talk to (`sel_tx`, `sel_rx` logic).
--       3. Interface Unification: It provides a single, unified bus interface
--          (`cs_n`, `wr_en`, `addr`, etc.) to the main system. The main SoC
--          design (`risc_soc.sv`) doesn't need to know about the internal
--          details of the TX and RX; it just talks to the `uart_top` peripheral.
--
-- Why is this used?
-- This design pattern is ubiquitous in the VLSI industry because it provides
-- several enormous benefits:
--
--   - Modularity and Reusability: The `uart_tx` and `uart_rx` modules can be
--     designed, tested, and verified independently. A different project might
--     only need a transmitter; it can just grab the `uart_tx.v` file and use
--     it. This promotes the creation of a library of reusable IP blocks.
--
--   - Manages Complexity: By hiding the internal details, the top-level design
--     becomes much cleaner and easier to understand. Imagine if the main SoC file
--     had to contain all the selection and muxing logic for every peripheral;
--     it would quickly become an unmanageable mess.
--
--   - Enables Parallel Development: In a professional team, one engineer could be
--     working on `uart_tx`, another on `uart_rx`, and a third on this `uart_top`
--     wrapper, all at the same time, as long as they agree on the interfaces
--     between the blocks beforehand.
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
-- The motive for creating `uart_top.v` was purely architectural. After
-- designing the `uart_tx` and `uart_rx` modules, I needed a clean and robust
-- way to present them to the main SoC bus. I could have put the address
-- decoding and muxing logic directly in the top-level `risc_soc.sv` file, but
-- that would have been poor design. It would have cluttered the top-level file
-- with details specific only to the UART. Creating this wrapper encapsulates
-- all UART-specific logic, adhering to the principle of modularity. The rest
-- of the system doesn't need to know that the UART is composed of two sub-
-- modules; it just sees a single "UART" peripheral at a specific address,
-- which is a much cleaner abstraction.
--
--
-- [[ My Coding Ethic and Process ]]
--
-- Since this module is purely structural, the process was different from the
-- FSM-heavy modules:
--
--   1. Define the Unified Interface: I started by defining the port list for
--      `uart_top`, which would be the single interface the rest of the system
--      would see.
--
--   2. Plan the Internal Address Map: I decided on a simple address decoding
--      scheme: use a single bit (`addr[2]`) to select between TX and RX. This
--      divides the UART's address space neatly in two, giving four register
--      locations to the TX and four to the RX.
--
--   3. Implement the Decoding Logic: I wrote the combinational logic for `sel_tx`,
--      `sel_rx`, `cs_tx_n`, and `cs_rx_n` to implement this address map. I used
--      ternary operators for conciseness and clarity.
--
--   4. Instantiate and Wire: The final step was to instantiate `u_uart_tx` and
--      `u_uart_rx` and carefully connect all their ports to the appropriate
--      top-level ports or internal wires. This step is essentially a digital
--      "wiring" or "schematic capture" process done in code. I double-checked
--      every connection, as a single mis-wired port is a common integration bug.
--
--
-- [[ Unit Testing Strategy ]]
--
-- This `uart_top` module is one of the few components in the project that does
-- not have its own dedicated unit test. This is a deliberate choice based on
-- its function.
--
--   - Why no unit test? This module contains no complex sequential logic, FSMs,
--     or data processing algorithms. Its logic is purely structural and
--     combinational (instantiations and simple assignments). The effort to create
--     a dedicated testbench that would also have to include mock versions of the
--     TX and RX modules would be significant and would provide little value over
--     what is already achieved in the system-level test.
--
--   - Verification through Integration: The correctness of this wrapper's logic
--     (the address decoding and muxing) is thoroughly and implicitly verified
--     by the system-level `UART_LOOPBACK_TEST`. For that test to pass, the CPU
--     must be able to write to the transmitter and read from the receiver. This
--     is only possible if the address decoding and wiring inside this `uart_top`
--     module are 100% correct. Therefore, a passing system-level test is
--     sufficient verification for this simple structural block.
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
-- The `uart_top` module is instantiated as `u_uart` in the main `risc_soc.sv`
-- design file. Its integration is that of a single, standard slave peripheral.
--
--   - Slave Port Wiring: The wrapper's unified bus interface is connected to
--     the main system bus. The `address_decoder` asserts the `uart_cs_n` signal
--     for any access in the `0x0005_xxxx` address range. This single chip
--     select enables the entire UART subsystem.
--
--   - Physical Pin and Interrupt Wiring:
--     - The `tx_pin` output of this module is connected to the top-level
--       `uart_tx_pin` of the SoC.
--     - The `rx_pin` input is connected to the top-level `uart_rx_pin`.
--     - The `irq_out` is connected as `irq2_in` to the `interrupt_controller`.
--
--   - System-Level Verification: As this module is purely structural, its
--     correctness is verified entirely by the `UART_LOOPBACK_TEST`. For that
--     test to pass, the CPU must successfully write to an address that selects
--     the transmitter, and then later read from an address that selects the
--     receiver. This implicitly proves that the internal address decoding and
--     muxing logic within this `uart_top` wrapper are functioning correctly.
--
--
-- [[ Industrial Applications ]]
--
-- The "wrapper" or "facade" design pattern embodied by this module is not just
-- a good practice; it is standard operating procedure in the VLSI industry for
-- managing the immense complexity of modern SoCs.
--
--   1. Complex IP Subsystems: A modern IP block, like a USB 3.0 controller or
--      a DDR memory controller, is not a single, monolithic FSM. It is a huge
--      subsystem composed of many smaller blocks (a protocol layer, a physical
--      layer, configuration registers, DMA engines, etc.). This entire subsystem
--      is delivered to the main SoC integration team as a single block with a
--      `..._top.v` wrapper, exactly like this `uart_top` module. The wrapper
--      hides the internal complexity and presents a clean, standardized bus
--      interface (e.g., AXI4) to the rest of the chip.
--
--   2. Third-Party IP Integration: Companies often purchase IP from vendors like
--      ARM, Synopsys, or Cadence. This IP is delivered as a "black box" with a
--      well-documented top-level wrapper. The SoC integrator's job is simply
--      to instantiate this wrapper and connect its ports according to the
--      datasheet, similar to how `u_uart` is instantiated in `risc_soc.sv`.
--
--   3. Design Abstraction: This pattern allows different teams to work at
--      different levels of abstraction. The core IP designers can focus on the
--      complex internal logic of the TX and RX modules, while the top-level SoC
--      integrator only needs to care about the unified interface provided by
--      the `uart_top` wrapper.
--
--
-- [[ Industrially Relevant Insights Gained ]]
--
--   - Technical Insight: The importance of a well-defined address map. The
--     decision to use `addr[2]` as the selector bit between the TX and RX sub-
--     modules was a key architectural choice. It cleanly partitions the address
--     space and makes the decoding logic trivial (`sel_tx = (addr[2] == 1'b0)`).
--     In a larger design, creating a clear, non-overlapping, and easy-to-decode
--     address map for all peripherals is one of the most important first steps
--     of the entire SoC architecture phase.
--
--   - Architectural Insight: Encapsulation is key to managing complexity. This
--     module taught me the value of hiding implementation details. By creating
--     this wrapper, the main `risc_soc.sv` file becomes simpler and more
--     readable. If I later decided to add a FIFO to the UART, I would only
--     need to modify the logic *inside* this `uart_top` wrapper; the top-level
--     SoC file and its port connections would not need to change at all, which
--     is a huge benefit for maintainability.
--
--   - Non-Technical Insight: Interfaces are contracts. The port list of this
--     module, along with the comments describing what each signal does, forms a
--     "contract" between this block and the rest of the system. In a professional
--     team setting, this contract (often a formal specification document) is
--     what allows different engineers to work in parallel with confidence,
--     knowing that if everyone adheres to the agreed-upon interfaces, the final
--     integrated system will work correctly.
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
-- Bug Symptom: During the `UART_LOOPBACK_TEST`, the test was completely failing.
-- The CPU would write to the transmitter, but nothing would happen. The testbench
-- would eventually time out because the receiver never received anything and
-- therefore never generated an interrupt.
--
-- My Debugging Process:
--
--   1. Hypothesis: Since this `uart_top` module is purely structural, the bug had
--      to be a simple wiring or logic error within it. My first hypothesis was
--      that I had an error in my sub-module select logic.
--
--   2. Evidence Gathering (Waveform Analysis): I opened GTKWave and added the
--      signals from within this wrapper module to the view. This is a key
--      debugging technique for hierarchical designs. I added:
--      - The main inputs: `cs_n`, `addr`.
--      - The internal select signals: `sel_tx`, `sel_rx`.
--      - The generated chip selects for the sub-modules: `cs_tx_n`, `cs_rx_n`.
--
--   3. The "Aha!" Moment: I looked at the waveform during the CPU write to the
--      transmitter's data register. The main `cs_n` was correctly asserted ('0')
--      and the `addr` was also correct (`4'h0`). This meant `addr[2]` was '0',
--      and the waveform confirmed that `sel_tx` correctly went high. However,
--      when I looked at the generated chip select, `cs_tx_n`, it was stuck high
--      (inactive). I looked at the logic again. In a previous version, I had
--      mistakenly written the logic as `wire cs_tx_n = !sel_tx ? cs_n : 1'b1;`.
--      I had inverted the condition. The logic was only asserting the chip
--      select when `sel_tx` was *false*.
--
-- The Fix: The fix was a simple inversion of the condition in the ternary
-- operator: `wire cs_tx_n = sel_tx ? cs_n : 1'b1;`. This ensured that the
-- sub-module's chip select would be passed through from the main `cs_n` only
-- when that sub-module was actually selected. This bug, while simple, was a
-- powerful lesson in methodically tracing signals through a design hierarchy
-- to pinpoint the exact location of a structural or wiring fault.
--
--
-- [[ Current Limitations ]]
--
--   1. Fixed Address Map: The address map, which uses `addr[2]` to select
--      between TX and RX, is hard-coded. This is inflexible if the sub-modules
--      ever change their internal register map sizes.
--   2. No Shared Resources: The wrapper simply passes signals through. It does
--      not contain any logic that might be shared between the TX and RX modules,
--      such as a shared baud rate generator or a shared status register.
--
--
-- [[ Future Improvements ]]
--
--   1. Parameterized Address Decoding: I would use Verilog parameters to define
--      the base addresses and address widths of the sub-modules. The decoding
--      logic would then be based on these parameters, making the wrapper much
--      more flexible and reusable if the underlying sub-modules are changed.
--
--   2. Add a Shared Baud Rate Generator: Instead of having both the TX and RX
--      modules calculate their own timing based on `CLKS_PER_BIT`, a more
--      efficient design would have a single, shared baud rate generator inside
--      this `uart_top` module. This generator would create a "baud tick" enable
--      signal that would be passed down to both the `uart_tx` and `uart_rx`
--      FSMs. This reduces redundant logic and ensures both halves are perfectly
--      synchronized to the same rate.
--
--   3. Unified Status and Control Registers: I would add registers directly
--      within this wrapper. For example, a single "UART Status Register" could
--      combine the `is_busy` flag from the transmitter and the `data_valid`
--      flag from the receiver into a single, easy-to-read location for the CPU.
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
-- The entire project was developed using a lightweight and powerful open-source
-- toolchain, which is ideal for focusing on core design principles.
--
--   - Coding Editor: Visual Studio Code (VS Code), customized with the
--     "Verilog-HDL/SystemVerilog" extension for syntax highlighting and linting.
--     Its integrated terminal was used for all command-line operations.
--
--   - Simulation Engine (EDA Tool): Icarus Verilog (`iverilog`). This free and
--     standards-compliant simulator was used to compile and run all tests.
--
--   - Waveform Viewer: GTKWave. This tool was crucial for debugging the logic
--     within this wrapper. By viewing the `cs_n`, `addr`, `sel_tx`, `sel_rx`,
--     `cs_tx_n`, and `cs_rx_n` signals together, I could instantly verify that
--     my address decoding logic was routing the chip selects correctly.
--
--   - Automation Scripting: Python 3. The `run_regression.py` script automates
--     the entire verification process, from compiling the design to parsing the
--     simulation logs for pass/fail results.
--
--
-- [[ Execution Commands ]]
--
-- The `run_regression.py` script automates the compilation and simulation flow.
-- Here are the underlying shell commands it generates to test the UART subsystem.
--
--   1. Compilation:
--      All design files are compiled into a single executable. The sub-modules
--      (`uart_tx.v`, `uart_rx.v`) must be compiled before this `uart_top.v`
--      wrapper, which in turn must be compiled before the top-level `risc_soc.sv`
--      file that instantiates it.
--
--      The command is:
--      `iverilog -g2005-sv -o soc_sim on_chip_ram.v crc32_accelerator.v timer.v uart_tx.v uart_rx.v uart_top.v address_decoder.v arbiter.v interrupt_controller.v dma_engine.v simple_cpu.v risc_soc.sv tb_risc_soc.sv`
--
--      - `iverilog`: The Verilog compiler.
--      - `-g2005-sv`: Enables SystemVerilog features used in the testbench.
--      - `-o soc_sim`: Specifies the name of the compiled output file.
--      - `[file list]`: The complete, dependency-ordered list of source files.
--
--   2. Simulation:
--      To verify this wrapper and its sub-modules, the script runs the loopback
--      test.
--
--      The command is:
--      `vvp soc_sim +TESTNAME=UART_LOOPBACK_TEST`
--
--      - `vvp`: The simulation runtime engine.
--      - `soc_sim`: The compiled executable.
--      - `+TESTNAME=UART_LOOPBACK_TEST`: This plusarg tells the testbench to
--        run the specific UART test. A passing result for this test inherently
--        proves that the address decoding and wiring within this `uart_top`
--        module are correct, as the test requires successful communication
--        with both the transmitter and receiver sub-modules.
--
--------------------------------------------------------------------------------
*/







