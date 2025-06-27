// Copyright (c) 2025 Kumar Vedang
// SPDX-License-Identifier: MIT
//
// This source file is part of the RISC-V SoC project.
//


/*
--------------------------------------------------------------------------------
-- Module Name: interrupt_controller
-- Project: A Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: Kumar Vedang
--------------------------------------------------------------------------------
--
-- High-Level Module Purpose:
-- This module, `interrupt_controller`, acts as the central nervous system for
-- handling asynchronous events within the SoC. Peripherals like the DMA, Timer,
-- or UART need a way to signal the CPU when a task is complete or requires
-- attention. However, a simple CPU core typically has only one interrupt input
-- pin. This controller solves that problem by managing multiple interrupt
-- sources and funneling them into a single, coherent signal for the CPU.
--
-- Significance in the SoC Architecture:
-- An interrupt controller is a non-negotiable component in any real-world
-- multitasking system. Its significance is threefold:
--   1. Aggregation: It takes multiple interrupt request lines (from the DMA,
--      Timer, etc.) and combines them into a single `irq_out` line that is fed
--      to the CPU.
--   2. Latching ("Sticky" Behavior): Peripherals might only assert their
--      interrupt signal for a single clock cycle. This controller "latches" or
--      "catches" these short pulses and holds the interrupt active until the
--      CPU explicitly acknowledges and clears it. This prevents missed events.
--   3. Status Reporting: When the CPU receives an interrupt, it needs to know
--      *who* caused it. This controller provides a memory-mapped status
--      register that the CPU can read to identify the source of the interrupt,
--      allowing it to jump to the correct Interrupt Service Routine (ISR).
--
-- Communication and Integration:
-- This module acts as a simple slave peripheral on the system bus.
--
--   - Receiving Interrupts: It receives `irq_in` signals from various
--     peripherals (DMA, Timer, UART).
--
--   - Interfacing with the CPU: The CPU interacts with this controller via the
--     slave bus interface. It can read the status register to determine the
--     interrupt source and perform a write to the controller's base address to
--     "acknowledge" and clear the latched interrupts.
--
--   - Signaling the CPU: Its primary output, `irq_out`, is connected directly
--     to the CPU's single interrupt input pin, triggering the CPU's internal
--     interrupt handling mechanism.
--
--------------------------------------------------------------------------------
*/

`timescale 1ns / 1ps


// This `module` declaration defines the boundary of the interrupt_controller.
// Its purpose is to manage and aggregate multiple interrupt sources into a
// single signal for the CPU.
module interrupt_controller (

    // --- System Signals ---

    // `clk`: A single-bit input for the system clock. All state-latching
    // logic within this module is synchronized to the rising edge of this clock.
    input        clk,


    // `rst_n`: A single-bit input for the active-low, asynchronous system reset.
    // When asserted ('0'), it clears all internal interrupt latches to a known-off state.
    input        rst_n,


    // --- Interrupt Inputs from Peripherals ---
    // Each of these inputs represents an interrupt request line from a specific
    // peripheral in the SoC.

    // `irq0_in`: Interrupt request from the DMA engine (`dma_done` signal).
    // This signal goes high when the DMA completes its transfer.
    input        irq0_in, //

    // `irq1_in`: Interrupt request from the Timer module. This signal goes high
    // when the timer's internal counter matches its programmed compare value.
    input        irq1_in, //

    // `irq2_in`: Interrupt request from the UART Receiver. This signal goes
    // high when the UART has successfully received a full byte of data.
    input        irq2_in, // 



    
    // --- CPU Bus Interface (for clearing and status) ---
    // This is a standard slave bus interface that allows the CPU to read the
    // status of the controller and clear pending interrupts.

    // `cs_n`: The active-low chip select. Driven by the `address_decoder` when
    // the CPU accesses the memory address range assigned to this controller.
    input        cs_n,


    // `wr_en`: The write enable signal from the CPU. It is '1' for a write
    // (which is used to clear interrupts) and '0' for a read (to get status).
    input        wr_en,

    // `addr`: The lower address bits from the CPU. In this simple design, any
    // access within the controller's range is treated the same, so this is not
    // heavily used, but it's part of the standard interface.
    input [3:0]  addr,


    // `rdata`: The 32-bit read data output. When the CPU performs a read, this
    // bus carries the value of the interrupt status register back to the CPU.
    output [31:0] rdata,



    // --- Final Interrupt Output to CPU ---
    // `irq_out`: This single-bit output is the final, combined interrupt signal
    // that is connected directly to the CPU's main interrupt input pin. It is the
    // logical OR of all latched internal interrupts.
    output       irq_out
);


    // --- Internal State Declaration (Interrupt Latches) ---
    // These single-bit registers (`reg`) are the memory elements of the
    // controller. Each one is responsible for "latching" or "catching" an
    // interrupt request from a specific peripheral. This is crucial because a
    // peripheral might only assert its interrupt for a single clock cycle.
    // These registers will "remember" that the interrupt occurred until the CPU
    // explicitly clears them. In hardware, each of these will be synthesized
    // into a single D-type flip-flop with set/reset logic.



    // `irq0_latched`: This register stores the latched state of the interrupt
    // request from the DMA (connected to `irq0_in`).
    reg irq0_latched;


    // `irq1_latched`: This register stores the latched state of the interrupt
    // request from the Timer (connected to `irq1_in`).
    reg irq1_latched;



    // `irq2_latched`: This register stores the latched state of the interrupt
    // request from the UART Receiver (connected to `irq2_in`).
    reg irq2_latched;



    // --- Combinational Logic for Final Interrupt Output ---
    // This `assign` statement creates a simple OR gate. It combines the states
    // of all the individual interrupt latches. If any one of the latches is
    // set to '1', the final `irq_out` signal to the CPU will be '1'.
    assign irq_out = irq0_latched | irq1_latched | irq2_latched;



    // --- Combinational Logic for the Status Register Read Path ---
    // This `assign` statement implements the read logic for the CPU.
    // If the controller is selected for a read (`!cs_n && !wr_en`), it builds a
    // 32-bit word to send back on `rdata`.
    // The `{...}` is the concatenation operator. It assembles the status word:
    //   - Bit 0: Value of the DMA interrupt latch (`irq0_latched`).
    //   - Bit 1: Value of the Timer interrupt latch (`irq1_latched`).
    //   - Bit 2: Value of the UART interrupt latch (`irq2_latched`).
    //   - Bits 31:3 are padded with zeros.
    // If not selected for a read, it drives high-impedance ('Z') to stay off the bus.
    assign rdata = (!cs_n && !wr_en) ? {29'b0, irq2_latched, irq1_latched, irq0_latched} : 32'hZZZZZZZZ;



    // --- Sequential Logic for Interrupt 0 (DMA) Latch ---
    // This `always` block defines the behavior of the `irq0_latched` register.
    // It's a flip-flop with prioritized set/reset logic.
    always @(posedge clk or negedge rst_n) begin

        // The highest priority is the asynchronous reset.
        if (!rst_n)
        irq0_latched <= 1'b0;

        // Immediately clear the latch on reset.
        // The next priority is a write from the CPU, which acts as a synchronous clear.
        // A write to this controller's address space clears the latch.
        else if (!cs_n && wr_en)
        irq0_latched <= 1'b0;


        // The lowest priority is the interrupt input itself.
        // If the `irq0_in` signal from the DMA is high, set the latch.
        else if (irq0_in)
        irq0_latched <= 1'b1;
    end


    // --- Sequential Logic for Interrupt 1 (Timer) Latch ---
    // This block is identical in structure to the one above, but it manages the
    // interrupt latch for the Timer peripheral.
    always @(posedge clk or negedge rst_n) begin

        // Asynchronous reset has highest priority.
        if (!rst_n)
        irq1_latched <= 1'b0;

        // Synchronous clear by the CPU has next priority.
        else if (!cs_n && wr_en)    
        irq1_latched <= 1'b0;

        // Setting the latch based on the Timer's input signal has lowest priority.
        else if (irq1_in)
        irq1_latched <= 1'b1;
    end


    // --- Sequential Logic for Interrupt 2 (UART) Latch ---
    // This block manages the interrupt latch for the UART peripheral.
    always @(posedge clk or negedge rst_n) begin

        // Asynchronous reset.
        if (!rst_n)
        irq2_latched <= 1'b0;


        // Synchronous clear by CPU write.
        else if (!cs_n && wr_en)
        irq2_latched <= 1'b0;


        // Set the latch if the UART asserts its interrupt request.
        else if (irq2_in)
        irq2_latched <= 1'b1;
    end

endmodule




/*
--------------------------------------------------------------------------------
-- Conceptual Deep Dive: Hardware Interrupts
--------------------------------------------------------------------------------
--
-- What is an Interrupt?
-- An interrupt is a signal sent from a hardware peripheral to the main
-- processor (CPU) that demands immediate attention. It temporarily "interrupts"
-- the CPU's current program flow, forcing it to save its context and execute a
-- special piece of code called an Interrupt Service Routine (ISR) to handle the
-- event. This mechanism is far more efficient than "polling," where the CPU would
-- have to waste time constantly checking the status of every peripheral.
--
-- Where is the concept used in this file?
-- This entire module is the physical embodiment of an interrupt handling system.
-- It implements three critical concepts of interrupt management:
--
--   1. Interrupt Aggregation: A CPU core typically has only one physical
--      interrupt input pin. This controller takes three separate interrupt
--      sources (`irq0_in`, `irq1_in`, `irq2_in`) and uses a simple OR gate
--      (`assign irq_out = ...`) to combine them into a single signal for the CPU.
--
--   2. "Sticky" Latching: Peripheral events can be fleeting. The DMA might
--      assert its `dma_done` signal for just one clock cycle. If the CPU is
--      busy, it could miss this pulse. To prevent this, this controller uses
--      "sticky" latches. Each `always` block implements a flip-flop that, once
--      set by an incoming `irq_in` signal, will *stay set* (remain "sticky")
--      even if the source signal goes away. The interrupt is "caught" and held.
--
--   3. Source Identification and Clearing: Once interrupted, the CPU needs to
--      know *which* peripheral needs service. The `assign rdata = ...` line
--      implements a read-only Status Register. The CPU reads this register to
--      see which of the internal latches (`irq0_latched`, etc.) is set, thereby
--      identifying the source. Furthermore, the logic `else if (!cs_n && wr_en)`
--      in each `always` block defines the "clearing" mechanism. After the ISR
--      is finished, the CPU performs a write to the controller's address. This
--      action clears the latch, resetting it so it can catch the next interrupt.
--
-- Why is this used?
-- Without an interrupt system, the only way for the CPU to know if the DMA was
-- finished would be to sit in a tight loop, constantly reading the DMA's status
-- register. This is called polling and is incredibly inefficient, as it wastes
-- 100% of the CPU's time. Interrupts allow the CPU to perform other useful work
-- and only switch its attention to a peripheral when absolutely necessary, which
-- is the foundation of all modern operating systems and real-time applications.
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
-- The moment I decided to include more than one peripheral capable of
-- signaling completion (like the DMA and Timer), the creation of an interrupt
-- controller became mandatory. The CPU core was designed with a single `irq_in`
-- port, which is a common and realistic constraint. My motive was to build the
-- essential "glue logic" that solves this many-to-one problem. I wanted to go
-- beyond just OR-ing the signals together; I needed to implement the full
-- "latch, status, and clear" mechanism that defines a truly functional
-- interrupt system and is required for robust software interaction.
--
--
-- [[ My Coding Ethic and Process ]]
--
-- For this module, my process was dictated by the strict requirements of
-- interrupt handling logic:
--
--   1. Priority Logic First: I first determined the logical priority for each
--      latch. The asynchronous reset (`rst_n`) must always be the highest
--      priority to guarantee a known starting state. The CPU's clear command
--      (`!cs_n && wr_en`) must have the next highest priority to ensure software
--      can always override a pending interrupt. The lowest priority is the
--      interrupt source itself (`irq_in`). This priority scheme is directly
--      reflected in the `if...else if...else if` structure of each `always` block.
--
--   2. Explicit Latching: I intentionally chose to implement three separate
--      `always` blocks, one for each interrupt latch. While it's possible to
--      combine them, separating them makes the logic for each interrupt source
--      explicit and independent. This reduces the chance of a coding error in
--      one block affecting the others and makes the design easier to debug and
--      expand in the future.
--
--   3. Status Register Design: I designed the `rdata` output to be a bitmask.
--      This is a standard industrial practice. Each bit in the status register
--      corresponds directly to one interrupt source. This allows the software
--      (or in our case, the testbench) to use simple bitwise operations to
--      quickly identify which peripheral(s) require service.
--
--
-- [[ Unit Testing Strategy ]]
--
-- The unit test for this module was particularly focused on timing and potential
-- race conditions, as these are common pitfalls in interrupt logic.
--
--   - Dedicated Testbench: I created `tb_interrupt_controller.v` which
--     instantiated only this module. The testbench had to drive all three
--     `irq_in` lines and the slave bus interface signals.
--
--   - Test Scenarios: My unit test included several key sequences:
--       1. Basic Latch Test: For each interrupt input, I would generate a
--          single-cycle pulse on the `irq_in` line and verify that the
--          corresponding `irq_out` went high and *stayed high*.
--       2. Clear Test: After a latch was set, I would simulate a CPU write and
--          verify that the `irq_out` was de-asserted on the next clock edge.
--       3. Status Read Test: I would set one or more latches and then simulate
--          a CPU read, verifying that the `rdata` bus presented the correct
--          bitmask (e.g., `32'h...0101` if IRQ0 and IRQ2 were active).
--       4. Priority Test (The most critical): I would assert an `irq_in` and a
--          CPU clear signal in the *same clock cycle* to verify that the clear
--          operation correctly took priority and the latch did not get set.
--
-- This thorough, priority-aware unit testing was essential for gaining
-- confidence in the design, as a faulty interrupt controller can cause some of
-- the most difficult-to-diagnose bugs at the system level.
--
--------------------------------------------------------------------------------
*/





/*
-- ############################################################################
-- ##                   System Integration and Verification                  ##
-- ############################################################################
--
--
-- [[ Integration into the Top-Level SoC ]]
--
-- The `interrupt_controller` is instantiated as `u_intc` in the `risc_soc.sv`
-- file. Its integration is what forms the complete event-signaling pathway of
-- the system.
--
--   1. Slave Port Wiring: The controller's slave interface (`cs_n`, `wr_en`,
--      etc.) is connected to the main system bus like any other peripheral.
--      The `address_decoder` is configured to assert `intc_cs_n` when an
--      access is made to the `0x0003_xxxx` address range, allowing the CPU to
--      read its status and clear its latches.
--
--   2. Interrupt Source Wiring: This is the most critical part of its
--      integration. Each of the controller's `irq_in` ports is connected to
--      the corresponding `irq_out` signal from a peripheral:
--      - `irq0_in` is connected to the `dma_done_irq` wire from the DMA.
--      - `irq1_in` is connected to the `timer_irq_out` wire from the Timer.
--      - `irq2_in` is connected to the `uart_irq_out` wire from the UART.
--
--   3. CPU Interrupt Connection: The final `irq_out` of this module is
--      connected to a top-level wire named `cpu_irq_in`. This wire is then
--      routed directly to the single interrupt input port of the `simple_cpu`
--      instance.
--
-- This wiring scheme establishes the full path: A peripheral (e.g., Timer)
-- finishes its task, asserts its interrupt output, which is then caught by
-- this controller's latch, which in turn asserts the final `irq_out` to the CPU.
--
--
-- [[ System-Level Verification Strategy ]]
--
-- The interrupt controller's functionality is implicitly and explicitly
-- verified by every system-level test that uses interrupts. The primary tests
-- for this are the `TIMER_TEST` and `UART_LOOPBACK_TEST`.
--
--   - Test Flow:
--     1. The testbench (e.g., in `run_timer_test`) uses the CPU BFM to program
--        a peripheral (the Timer) and enable it.
--     2. The testbench then issues a `wait (dut.cpu_irq_in == 1'b1);` statement.
--        This is the core of the test; the testbench pauses and waits for the
--        entire interrupt chain to function correctly.
--     3. Once the interrupt fires, the testbench's scoreboard proceeds.
--
--   - Scoreboard Checks:
--     1. Source Identification Verification: The testbench immediately performs a
--        CPU BFM read from the interrupt controller's status register address
--        (`0x0003_0000`). It then checks the returned bitmask. For the
--        `TIMER_TEST`, it verifies that bit 1 is set and all other bits are
--        clear. This proves the correct interrupt was latched and reported.
--     2. Clearing Mechanism Verification: The testbench then performs a CPU
--        BFM write to the interrupt controller's address to clear the latch.
--        Crucially, it also writes to the source peripheral (e.g., the Timer)
--        to clear its internal status flag. It then waits a few cycles and
--        checks that `dut.cpu_irq_in` has gone low and *stayed low*. This
--        verifies the entire clearing mechanism.
--
-- A "PASS" in these tests confirms that the controller can successfully
-- latch, report, and clear interrupts from specific sources within the fully
-- integrated system.
--
--------------------------------------------------------------------------------
*/







/*
-- ############################################################################
-- ##                    Industrial Context and Insights                     ##
-- ############################################################################
--
--
-- [[ Industrial Applications ]]
--
-- This simple 3-input controller is a miniature version of one of the most
-- critical IP blocks in any complex SoC: the system-level Interrupt Controller.
-- In the industry, these are far more sophisticated, but they are based on the
-- exact same principles of latching, status reporting, and clearing.
--
--   1. ARM's Generic Interrupt Controller (GIC): This is the industry standard
--      interrupt controller used in virtually all ARM-based SoCs (e.g., in
--      smartphones, servers, automotive systems). A GIC is a highly
--      configurable IP that can manage hundreds of interrupt sources from all
--      over the chip. It handles complex tasks that this simple controller
--      doesn't, such as:
--      - Interrupt Prioritization: It can be programmed to ensure that a high-
--        priority interrupt (e.g., from a system watchdog timer) can interrupt
--        the service routine of a lower-priority one (e.g., a touchscreen input).
--      - Interrupt Distribution: In a multi-core CPU system, the GIC is
--        responsible for intelligently routing an interrupt to a specific CPU
--        core for handling.
--
--   2. RISC-V Platform-Level Interrupt Controller (PLIC): In the RISC-V
--      ecosystem, the PLIC serves the same purpose as ARM's GIC. It is a
--      standardized component that aggregates interrupts from across the SoC
--      and presents them to one or more RISC-V CPU cores.
--
--   3. Real-Time Operating Systems (RTOS): The functionality of a hardware
--      interrupt controller is essential for any RTOS. The OS scheduler relies
--      on a periodic interrupt from a system timer to perform context
--      switching between different software tasks. The ability of the hardware
--      to latch, prioritize, and identify interrupt sources is what enables
--      the software to manage a complex, multi-threaded environment. This simple
--      controller provides the bare minimum hardware support needed for such
--      a system.
--
--
-- [[ Industrially Relevant Insights Gained ]]
--
-- Designing and testing this module drove home several critical points relevant
-- to professional design:
--
--   - Technical Insight: The software/hardware contract is paramount. The
--     behavior of this controller is defined by an implicit "contract" with
--     the software (or testbench) that will run on the CPU. The hardware
--     promises to latch any interrupt and hold it. The software, in return,
--     promises that its Interrupt Service Routine will *always* clear the
--     interrupt at the controller to re-arm it. If either side breaks this
--     contract, the system fails. This taught me that designing an IP block is
--     as much about defining and documenting its expected usage model as it is
--     about the Verilog itself.
--
--   - Design-for-Verification Insight: The priority of the clear signal over
--     the set signal is a deliberate and critical design choice for testability.
--     If the `irq_in` had higher priority, a "stuck" peripheral holding its
--     interrupt high would make it impossible for the CPU to ever clear the
--     interrupt, creating a non-recoverable "interrupt storm." By giving the
--     CPU's clear command priority, we ensure that the system software can
--     always regain control and mask a faulty interrupt source, which is a
--     much more robust design.
--
--   - Non-Technical Insight: Scalability must be designed in from the start.
--     I intentionally used three separate `always` blocks for the three latches.
--     This design pattern is highly scalable. To add a fourth interrupt source,
--     one would simply add a new input (`irq3_in`), a new latch (`irq3_latched`),
--     and a new `always` block. The existing logic for IRQ0, 1, and 2 would not
--     need to be touched. This modular approach is key to managing complexity
--     and enabling parallel development in large engineering teams.
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
-- Bug Symptom: The "back-to-back DMA" corner case test was failing. The first
-- DMA transfer would complete successfully and fire an interrupt. The testbench
-- would service it. But when the testbench started the second DMA transfer, an
-- interrupt would fire *immediately*, long before the second transfer could
-- have possibly finished, causing the test's scoreboard to fail.
--
-- My Debugging Process:
--
--   1. Hypothesis: Initially, I was convinced the bug was in this interrupt
--      controller. I thought my clear logic was faulty and wasn't properly
--      clearing the `irq0_latched` register, leaving a "stale" interrupt active.
--
--   2. Evidence Gathering (Waveform Analysis): I opened GTKWave and focused on
--      the entire interrupt chain at the boundary between the two transfers. I
--      added the following signals:
--      - The raw interrupt from the source: `dut.u_dma.dma_done`
--      - The internal latch in this module: `dut.u_intc.irq0_latched`
--      - The final output to the CPU: `dut.cpu_irq_in`
--      - The bus signals (`bus_addr`, `bus_wr_en`) to see the testbench's actions.
--
--   3. The "Aha!" Moment: The waveform was the source of truth. It showed that
--      after the first transfer, my testbench BFM correctly wrote to the
--      interrupt controller's address (`0x0003_0000`). I could see `irq0_latched`
--      and `cpu_irq_in` correctly go to '0'. The controller was working perfectly!
--      However, as I stepped forward one cycle, I saw `irq0_latched` go right
--      back to '1'. Puzzled, I looked at the source signal, `dut.u_dma.dma_done`,
--      and realized it had *never gone low*. The bug was not in my controller;
--      it was in my testbench's Interrupt Service Routine (ISR).
--
-- The Fix: A real ISR must do two things: 1) Clear the interrupt at the central
-- controller (which I was doing), and 2) Clear the status flag at the source
-- peripheral that caused the interrupt (which I was *not* doing). Because the
-- DMA's internal `dma_done_reg` was still high, it was simply re-asserting its
-- interrupt request, and my perfectly functional controller was correctly re-
-- latching it. The fix was to modify the testbench BFM to add a second write
-- to the DMA's own status/clear register after servicing the interrupt. This
-- was a powerful lesson: often the bug is not in the DUT, but in the testbench
-- that is creating an unrealistic scenario.
--
--
-- [[ Current Limitations ]]
--
--   1. No Interrupt Masking: A crucial feature of industrial controllers is
--      the ability to "mask" or disable individual interrupts. This controller
--      lacks a mask register. The CPU has no way to tell the controller to
--      temporarily ignore interrupts from the Timer while it services a more
--      critical DMA interrupt, for example.
--   2. No Prioritization: All interrupts are treated equally. The final
--      `irq_out` is a simple OR of all sources. A real controller would have a
--      priority encoder to ensure that if multiple interrupts fire at once,
--      it can report the highest-priority one to the CPU.
--   3. Single Clear Action: A write to any address in the controller's space
--      clears *all* latched interrupts. A more granular design would allow the
--      CPU to clear specific latches individually.
--
--
-- [[ Future Improvements ]]
--
--   1. Implement an Interrupt Mask Register: I would add a 32-bit `mask_reg`
--      and a corresponding memory-mapped address for it. The final `irq_out`
--      logic would be changed from `assign irq_out = irq0_latched | ...` to
--      `assign irq_out = (irq0_latched & mask_reg[0]) | (irq1_latched & mask_reg[1]) | ...`.
--      This would allow the CPU to dynamically enable or disable each interrupt source.
--
--   2. Add a Priority Encoder: I would add logic that, if multiple latches are
--      set, only reports the highest-priority interrupt number in a separate
--      "current pending" register that the CPU could read. This is essential
--      for building a system that can handle nested interrupts correctly.
--
--   3. Granular Clearing: I would modify the write logic so that the data
--      written by the CPU (`wdata`) acts as a bitmask for clearing. For example,
--      writing a `1` to bit 0 of `wdata` would clear `irq0_latched` but leave the others
--      untouched. This provides much finer software control.
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
-- The toolchain for this project was deliberately kept open-source and simple
-- to focus on fundamental design principles and ensure maximum portability.
--
--   - Coding Editor: Visual Studio Code (VS Code). Chosen for its speed and
--     the power of its integrated terminal and extensions. The "Verilog-HDL/
--     SystemVerilog" extension provided essential syntax highlighting and
--     linting capabilities.
--
--   - Simulation Engine (EDA Tool): Icarus Verilog (`iverilog`). A robust and
--     standards-compliant open-source simulator. Its strict interpretation of
--     the Verilog standard helped ensure the RTL for this module was clean and
--     unambiguous, particularly the prioritized set/reset logic in the `always`
--     blocks.
--
--   - Waveform Viewer: GTKWave. This tool was my "oscilloscope" for the digital
--     world. It was essential for visualizing the timing relationships between
--     the peripheral `irq_in` signals, the internal `..._latched` registers,
--     the CPU's clear command, and the final `irq_out`, which was key to
--     debugging the "stale interrupt" testbench issue.
--
--   - Automation Scripting: Python 3. The `run_regression.py` script uses
--     Python to orchestrate the entire verification flow, demonstrating a key
--     industry practice for managing complex test suites.
--
--
-- [[ Execution Commands ]]
--
-- The `run_regression.py` script automates the compilation and simulation. The
-- commands it generates are executed in a standard shell or terminal.
--
--   1. Compilation:
--      All design files, including this `interrupt_controller.v`, are compiled
--      into a single simulation executable. This module must be compiled
--      before the top-level `risc_soc.sv` which instantiates it.
--
--      The command is:
--      `iverilog -g2005-sv -o soc_sim on_chip_ram.v crc32_accelerator.v timer.v uart_tx.v uart_rx.v uart_top.v address_decoder.v arbiter.v interrupt_controller.v dma_engine.v simple_cpu.v risc_soc.sv tb_risc_soc.sv`
--
--      - `iverilog`: The compiler executable.
--      - `-g2005-sv`: Flag to enable SystemVerilog features for the testbench.
--      - `-o soc_sim`: Specifies the name of the output executable.
--      - `[file list]`: The complete, ordered list of all source files.
--
--   2. Simulation:
--      To verify this controller's functionality, the script runs tests that
--      rely on interrupts. For example, to run the timer test:
--
--      The command is:
--      `vvp soc_sim +TESTNAME=TIMER_TEST`
--
--      - `vvp`: The simulation runtime engine.
--      - `soc_sim`: The compiled executable file.
--      - `+TESTNAME=TIMER_TEST`: The plusarg passed to the testbench. The
--        `tb_risc_soc.sv` reads this argument and executes the `run_timer_test`
--        task. That task specifically configures the timer, waits for the
--        interrupt from this controller, and then reads this controller's
--        status register to verify that the correct interrupt (bit 1) was
--        latched. This provides end-to-end verification of the IRQ1 path.
--
--------------------------------------------------------------------------------
*/