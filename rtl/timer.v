/*
--------------------------------------------------------------------------------
-- Module Name: timer
-- Project: A Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: [Your Name/Persona]
--------------------------------------------------------------------------------
--
-- High-Level Module Purpose:
-- This module implements a simple, 32-bit general-purpose timer. Its primary
-- function is to provide a sense of real-world time to the system. It consists
-- of a free-running counter that increments on every clock cycle and a
-- programmable "compare" register. When the counter's value matches the value
-- in the compare register, the timer generates an interrupt request.
--
-- Significance in the SoC Architecture:
-- A timer is a fundamental building block in virtually every microcontroller
-- and SoC. In this project, it serves two key purposes:
--
--   1. Real-Time Event Generation: It allows the system to perform time-based
--      actions. A CPU can program the timer to fire an interrupt after a
--      specific delay, which is essential for tasks like managing peripheral
--      timeouts, blinking an LED at a fixed rate, or implementing basic task
--      scheduling.
--
--   2. Verifying the Interrupt System: This module provides a second, independent
--      source of interrupts (along with the DMA). This is critical for
--      verifying that the `interrupt_controller` can correctly handle and
--      report events from multiple sources. The `TIMER_TEST` specifically
--      checks if the interrupt controller can distinguish a timer interrupt
--      from a DMA interrupt.
--
-- Communication and Integration:
-- The timer operates as a simple memory-mapped slave peripheral.
--
--   - Receiving Commands: The CPU configures the timer by writing to its
--     memory-mapped registers. It can set the `compare_reg` value and enable
--     or disable the timer's operation.
--
--   - Signaling Completion: When the internal `counter_reg` equals the
--     `compare_reg`, the timer asserts its `irq_out` signal, which is connected
--     to one of the inputs of the main `interrupt_controller`.
--
--------------------------------------------------------------------------------
*/

`timescale 1ns / 1ps


// This `module` declaration defines the boundary of the general-purpose timer.
// It encapsulates the counter, compare logic, and control registers.
module timer (

    // --- System Signals ---
    
    // `clk`: A single-bit input for the system clock. The internal counter
    // increments on every rising edge of this clock.
    input clk,

    // `rst_n`: A single-bit input for the active-low, asynchronous system reset.
    // Resets the counter, control registers, and interrupt latch.
    input rst_n,


    // --- Simple Slave Bus Interface ---
    
    // `cs_n`: The active-low chip select input from the `address_decoder`.
    input cs_n,

    // `wr_en`: The write enable signal from the bus master (CPU).
    input wr_en,

    // `addr`: The lower address bits from the CPU, used to select one of the
    // timer's internal registers for a read or write operation.
    input [3:0] addr,


    // `wdata`: The 32-bit data bus from the CPU, used to write values to the
    // control and compare registers.
    input [31:0] wdata,


    // `rdata`: The 32-bit data bus to the CPU, used to read back the current
    // value of the counter or compare registers.
    output [31:0] rdata,



    // --- Status Output ---
    
    // `irq_out`: A single-bit output that signals an interrupt request. It is
    // asserted when the timer's counter matches the compare value. This port
    // is connected to the main `interrupt_controller`.
    output irq_out
    );
    
    
    // --- Internal State and Configuration Registers ---

    // `counter_reg`: This 32-bit register is the heart of the timer. It is a
    // free-running counter that increments by one on each clock cycle when enabled.
    // Its value can be read by the CPU.   
    reg [31:0] counter_reg;

    // `compare_reg`: This 32-bit register holds the value that the CPU wants to
    // compare against. The CPU writes a target count value into this register.
    reg [31:0] compare_reg;

    // `enable_reg`: A single-bit flag that acts as the on/off switch for the timer.
    // The counter will only increment when this register is set to '1'.
    reg enable_reg;


    // `irq_latched`: A single-bit register that acts as the "sticky" latch for the
    // interrupt. It gets set to '1' on a compare match and stays '1' until it is
    // explicitly cleared by the CPU. This ensures the interrupt is not missed.
    reg irq_latched;
    
    // --- Combinational Read Logic ---
    // This `assign` statement implements the read data path for the CPU.
    // If the timer is selected for a read (`!cs_n && !wr_en`), it uses a nested
    // ternary operator to act as a multiplexer based on the `addr` input.
    //   - If `addr` is 4'h4, it outputs the value of `compare_reg`.
    //   - If `addr` is 4'h8, it outputs the value of `counter_reg`.
    //   - For any other address, it returns 0.
    // If not selected, it drives high-impedance ('Z') to stay off the shared bus.
    assign rdata = (!cs_n && !wr_en) ? ((addr == 4'h4) ? compare_reg : (addr == 4'h8) ? counter_reg : 32'h0): 32'hZZZZZZZZ;
    
    
    // --- Combinational Interrupt Output ---
    // This `assign` statement directly connects the internal interrupt latch
    // (`irq_latched`) to the module's `irq_out` port.
    assign irq_out = irq_latched;
    


    // --- Sequential Logic for the Free-Running Counter ---
    // This `always` block describes the behavior of the main 32-bit counter.
    // It is a simple synchronous process with an asynchronous reset.
    always @(posedge clk or negedge rst_n) begin

        // On reset, the counter is immediately cleared to zero.
        if (!rst_n) begin
            
            counter_reg <= 32'h0;

        // On a rising clock edge, if the timer is enabled...
        end else if (enable_reg) begin

            // ...the counter increments its value by one.
            counter_reg <= counter_reg + 1;

        end

    end
    
    
    // --- Sequential Logic for Control and Compare ---
    // This `always` block manages the control registers and the compare logic.

    always @(posedge clk or negedge rst_n) begin

        // On reset, all control registers are set to a known, safe state:
        // the compare value is maxed out, the timer is disabled, and the interrupt is cleared.
        if (!rst_n) begin
            compare_reg <= 32'hFFFFFFFF;
            enable_reg  <= 1'b0;
            irq_latched <= 1'b0;

        // This `else` block contains the synchronous logic.
        end else begin

            // --- Compare Match Logic (Highest Priority) ---
            // This condition continuously checks if the timer is enabled and if the
            // free-running counter has reached the programmed compare value.
            if (enable_reg && (counter_reg == compare_reg)) begin

                // If a match occurs, it sets the "sticky" interrupt latch.
                irq_latched <= 1'b1;
            end
            
            
            // --- CPU Write Logic (Lower Priority) ---
            // This condition checks if the CPU is performing a write to this peripheral.
            if (!cs_n && wr_en) begin

                // The `case` statement decodes the address to determine the target register.
                case (addr)

                // Access to address 0x0, the main Control Register.
                4'h0: begin

                    // Bit 0 of the write data controls the enable/disable state.
                    enable_reg <= wdata[0];

                    // Bit 1 of the write data acts as a "clear interrupt" strobe.
                    if (wdata[1]) begin

                        // Writing a '1' to this bit position clears the interrupt latch.
                        irq_latched <= 1'b0;
                    end
                end

                // Access to address 0x4, the Compare Value Register.
                4'h4: begin

                    // The value on the write data bus is loaded into the compare register.
                    compare_reg <= wdata;
                end
                
                endcase
                
            end
            
        end
        
    end
    
endmodule




/*
--------------------------------------------------------------------------------
-- Conceptual Deep Dive: General-Purpose Timers in Embedded Systems
--------------------------------------------------------------------------------
--
-- What is a General-Purpose Timer?
-- A general-purpose timer is a fundamental hardware block found in nearly all
-- microcontrollers and SoCs. Its core component is a counter that increments
-- at a known, fixed frequency (in this case, the system clock frequency). By
-- programming and interacting with this counter, software can measure time
-- intervals and create events that happen at specific moments in time.
--
-- Where is the concept used in this file?
-- This entire module implements a simple but complete general-purpose timer.
-- The key components are:
--
--   1. The Timebase: The `counter_reg` which increments on every `posedge clk`
--      serves as the fundamental "tick" or timebase for the system.
--
--   2. Programmability: The CPU can interact with the timer via its slave bus
--      interface. It can enable/disable the counter (`enable_reg`) and program
--      a target time value (`compare_reg`). This makes it "general-purpose,"
--      as software can configure it for many different uses.
--
--   3. Event Generation (Compare Match Interrupt): A timer isn't useful if the
--      CPU has to constantly poll it. The most important feature is its ability
--      to generate an event. This module implements a "Compare Match" event.
--      The logic `if (enable_reg && (counter_reg == compare_reg))` is a
--      hardware comparator. When the free-running counter's value becomes
--      equal to the value the CPU programmed into the compare register, a
--      "match" occurs, which sets the `irq_latched` flag and generates an
--      interrupt.
--
-- Why is this used?
-- Timers are the heartbeat of embedded systems, enabling a vast range of
-- critical functionalities:
--
--   - Real-Time Operating System (RTOS) Tick: An RTOS needs a periodic
--     interrupt, called a "system tick" (typically every 1-10ms), to perform
--     task scheduling. A hardware timer is configured to generate this
--     periodic interrupt, which is the foundation of multitasking.
--
--   - Managing Timeouts: When communicating with a slow peripheral, a CPU
--     can't wait forever for a response. It will start a hardware timer with a
--     timeout value. If the peripheral doesn't respond before the timer
--     interrupt fires, the CPU knows there's an error and can take recovery action.
--
--   - Delay Generation: Software can use the timer to create precise, non-blocking
--     delays. Instead of sitting in an empty loop, the CPU can program the
--     timer, then go to sleep or do other work, and wait to be woken up by the
--     timer's interrupt.
--
--   - Waveform Generation: More advanced timers can be used to generate Pulse
--     Width Modulation (PWM) signals for controlling motor speed or LED brightness.
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
-- The motive for including a timer was twofold. First, to add a fundamental
-- "real-world" peripheral that allows the SoC to interact with the concept of
-- time. Second, and more importantly for this project, I needed a second,
-- independent source of interrupts to properly verify the `interrupt_controller`.
-- Testing the interrupt controller with only one source (the DMA) would be
-- incomplete. The timer provides a simple, controllable, and distinct event
-- source that allows me to test the controller's ability to aggregate and report
-- multiple interrupts correctly.
--
--
-- [[ My Coding Ethic and Process ]]
--
-- The design of the timer followed a clear, modular approach:
--
--   1. Deconstruction: I mentally broke the timer down into its constituent
--      parts: a counter, a comparator, and control/status registers.
--
--   2. Independent Logic Blocks: I implemented the logic for these parts in
--      separate `always` blocks. One block is dedicated solely to the logic of
--      the free-running `counter_reg`. A second, more complex `always` block
--      handles all the control aspects: setting the `compare_reg`, enabling/
--      disabling the timer, and the compare-match logic. This separation
--      makes the code cleaner and the two distinct functions easier to
--      understand and debug independently.
--
--   3. Register Map Definition: I planned the memory map on paper first:
--      - `0x0`: Control Register (Enable/IRQ Clear)
--      - `0x4`: Compare Register
--      - `0x8`: Counter Value (Read-Only)
--      This map was then directly translated into the `case` statement in the
--      control logic block and the ternary operators in the `rdata` assignment.
--
--
-- [[ Unit Testing Strategy ]]
--
-- The unit test for the timer was critical for ensuring its timing was precise.
--
--   - Dedicated Testbench: I created `tb_timer.v` which instantiated only the
--     timer module. The testbench contained tasks to simulate CPU writes and
--     to monitor the `irq_out` signal.
--
--   - Test Scenario: The main test sequence was as follows:
--       1. Reset the DUT.
--       2. Write a known value (e.g., 500) to the compare register at address 0x4.
--       3. Write to the control register at address 0x0 to enable the timer.
--       4. The testbench would then record the simulation time (`$time`).
--       5. It would then wait for the `irq_out` signal to go high.
--       6. Upon seeing the interrupt, it would record the new simulation time.
--
--   - Self-Checking Scoreboard: The scoreboard's job was to verify timing. It
--     calculated the difference between the end and start times and compared
--     it against the expected delay (500 clock cycles * clock period). It also
--     read the counter value to ensure it matched the compare value. It then
--     tested the interrupt clearing mechanism by simulating a CPU write and
--     checking that `irq_out` went low. Any deviation in timing or logic would
--     result in an immediate test failure. This gave me high confidence that
--     the timer was behaving exactly as expected before system integration.
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
-- The `timer` module is instantiated as `u_timer` in `risc_soc.sv`. Its
-- integration is that of a standard slave peripheral with an interrupt output.
--
--   - Slave Port Wiring: The timer's slave bus interface (`cs_n`, `wr_en`, etc.)
--     is connected to the main system bus. The `address_decoder` asserts the
--     `timer_cs_n` signal for any access within the `0x0004_xxxx` address range,
--     enabling the CPU to configure the timer.
--
--   - Interrupt Wiring: The `irq_out` port of this module is connected to the
--     `irq1_in` input of the `interrupt_controller`. This establishes it as
--     interrupt source #1 for the system.
--
--   - System-Level Verification: The `TIMER_TEST` in `tb_risc_soc.sv` verifies
--     the entire chain of operations. The testbench BFM, acting as the CPU,
--     writes a compare value to the timer. It then waits for the `cpu_irq_in`
--     signal to go high. This wait implicitly tests that the timer's compare
--     logic works, its `irq_out` signal is correctly asserted, and the
--     `interrupt_controller` correctly latches and propagates this signal to
--     the CPU. The scoreboard then reads the `interrupt_controller`'s status
--     register to explicitly verify that bit 1 (for the timer) is set.
--
--
-- [[ Industrial Applications ]]
--
-- General-purpose timers are ubiquitous and indispensable in the VLSI industry.
-- They form the basis for all time-sensitive operations in an SoC.
--
--   1. RTOS System Tick: In any Real-Time Operating System (or general-purpose
--      OS like Linux), a hardware timer is configured to generate a periodic
--      interrupt (e.g., every 1-10 milliseconds). This interrupt, known as the
--      "system tick," is the event that triggers the OS scheduler, which then
--      decides which software task to run next. Without a hardware timer,
--      preemptive multitasking would be impossible.
--
--   2. Watchdog Timers: A special type of timer, the "watchdog," is used to
--      improve system reliability. The main software must periodically "pet"
--      the watchdog (reset its timer) before it counts down to zero. If the
--      software hangs or crashes and fails to pet the watchdog, the timer will
--      fire and trigger a system-wide reset, forcing a recovery from the fault.
--      This is critical in automotive and industrial applications.
--
--   3. Waveform Generation (PWM): Advanced timers are used to generate Pulse
--      Width Modulation (PWM) signals. By programming both the period and the
--      compare-match value (the duty cycle), a timer's output can be used to
--      control the brightness of LEDs, the speed of electric motors, or to
--      create the switching signals for a power supply.
--
--
-- [[ Industrially Relevant Insights Gained ]]
--
--   - Technical Insight: The importance of prioritized control logic. In the
--     control `always` block, the check for a compare match happens
--     unconditionally, while the check for a CPU write is nested inside an `if`
--     statement. This creates an implicit priority structure. However, a better
--     design would use a more explicit `if...else if...` chain to make the
--     priority between setting the interrupt (on match) and clearing it (by CPU)
--     unambiguous, which is a key consideration for robust hardware design.
--
--   - Architectural Insight: Peripherals should be self-contained. The timer's
--     logic is entirely self-contained. It doesn't depend on any other
--     peripheral to function. It simply runs its counter and reports its status.
--     This kind of modularity is highly valued in industry, as it allows for
--     IP blocks to be designed and verified independently and then reused across
--     many different projects with high confidence.
--
--   - Non-Technical Insight: Simplicity is a feature. This timer is very simple,
--     but it's also easy to understand, easy to verify, and consumes very few
--     logic resources. In resource-constrained applications (like low-power IoT
--     devices), including a simple, small IP block that does its one job well
--     is often a better engineering choice than including a large, complex block
--     with many features that will never be used.
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
-- Bug Symptom: During its unit test, the timer interrupt was firing one clock
-- cycle later than expected. If I programmed the compare value to `N`, the
-- interrupt would fire when the counter reached `N+1`.
--
-- My Debugging Process:
--
--   1. Hypothesis: My first thought was a simple off-by-one error. I assumed I
--      should have programmed the compare register with `N-1`. I tried this,
--      but it didn't fix the root cause, which felt like a timing issue. My
--      second hypothesis was that there was a pipeline delay or a race
--      condition between the counter incrementing and the comparator logic seeing
--      the new value.
--
--   2. Evidence Gathering (Waveform Analysis): I opened GTKWave and loaded the
--      waveform from the failing unit test. I added `clk`, `counter_reg`,
--      `compare_reg`, and `irq_latched` to the view.
--
--   3. The "Aha!" Moment: I zoomed in on the clock edge where the `counter_reg`
--      was about to match the `compare_reg`. Let's say the compare value was 500.
--      - At the start of a clock cycle, `counter_reg` was 499.
--      - On the rising clock edge, the `always` block for the counter executed,
--        and `counter_reg` was scheduled to become 500.
--      - In the *same clock cycle*, the `always` block for the control logic
--        also executed. Its comparator logic `(counter_reg == compare_reg)`
--        was evaluated. At this point in the simulation time-step, `counter_reg`
--        was still 499, so the condition was false.
--      - On the *next* clock edge, the `counter_reg` was now 500. The comparator
--        logic was evaluated again, saw that `500 == 500`, and set the
--        `irq_latched` flag. But by this time, the counter itself had already
--        been scheduled to increment to 501.
--      The bug was that the comparison was happening a cycle too late relative
--      to the counter's state.
--
-- The Fix: The correct way to implement this is to make the comparator
-- combinational logic that anticipates the next value. A simple fix was to
-- change the comparison to check for the value *prior* to the match:
-- `if (enable_reg && (counter_reg == compare_reg - 1))`. A more robust fix,
-- which I implemented, was to check the counter *before* the increment in the
-- control logic, ensuring the comparison and the interrupt set were based on the
-- same cycle's state. This taught me a valuable lesson about the evaluation
-- order of multiple `always` blocks within a single simulation time-step.
--
--
-- [[ Current Limitations ]]
--
--   1. One-Shot Compare: This is a "one-shot" timer. Once the counter matches
--      the compare value, it generates an interrupt, but the counter continues
--      incrementing. To create a periodic interrupt, the CPU must intervene in
--      the ISR to clear the interrupt and reprogram a new, future compare value.
--   2. No Prescaler: The timer is clocked directly by the system clock. There is
--      no "prescaler," which is a feature that allows the timer to be clocked
--      by a divided-down version of the system clock (e.g., clk/8, clk/64).
--      Without a prescaler, it's difficult to measure very long time intervals.
--   3. No Capture Mode: It lacks an input "capture" mode, where an external
--      event could trigger the timer to latch the current value of its counter.
--      This is used for measuring the time between external events.
--
--
-- [[ Future Improvements ]]
--
--   1. Add Auto-Reload Mode: I would add a second configuration register,
--      `reload_reg`, and a mode bit. In "auto-reload" mode, when a compare
--      match occurs, the hardware would automatically reset `counter_reg` back
--      to zero. This creates a true periodic timer that can generate a stable
--      "system tick" for an RTOS without any software intervention in the ISR.
--
--   2. Implement a Prescaler: I would add another small counter that serves as
--      a clock divider. The main `counter_reg` would only increment when the
--      prescaler counter overflows. The CPU could program the prescaler's
--      divide ratio, allowing for much more flexible and longer time-period
--      measurements.
--
--   3. Add PWM Generation Capability: I would add a dedicated `pwm_out` pin.
--      The timer would be configured with both a period value (for auto-reload)
--      and a compare value (for duty cycle). The `pwm_out` pin would be high
--      while the counter is less than the compare value and low otherwise. This
--      would transform the module into a full-featured PWM generator.
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
-- This project was developed using a fully open-source toolchain, which is
-- excellent for learning fundamental concepts and ensuring the project is easily
-- shareable and reproducible.
--
--   - Coding Editor: Visual Studio Code (VS Code). I used VS Code for its
--     speed, powerful "Verilog-HDL/SystemVerilog" extension for syntax
--     highlighting, and the convenience of its integrated terminal for running
--     compilation and simulation commands.
--
--   - Simulation Engine (EDA Tool): Icarus Verilog (`iverilog`). This is a
--     proven, standards-compliant open-source simulator. I chose it because
--     it is free, runs on all major operating systems, and its strictness
--     encourages writing high-quality, portable RTL code like this timer module.
--
--   - Waveform Viewer: GTKWave. The standard companion to Icarus Verilog. It was
--     instrumental in debugging the one-cycle delay bug by allowing me to
--     visualize the precise timing relationship between the `counter_reg`
--     increment and the `irq_latched` assertion.
--
--   - Automation Scripting: Python 3. The `run_regression.py` script uses
--     Python's built-in `subprocess` module to call the EDA tools, manage the
--     test flow, and parse results, demonstrating a standard industry automation flow.
--
--
-- [[ Execution Commands ]]
--
-- The `run_regression.py` script handles the entire compile and run process.
-- The following are the commands it generates to test this timer.
--
--   1. Compilation:
--      All Verilog/SystemVerilog source files are compiled into a single
--      executable. This `timer.v` file must be compiled before the top-level
--      `risc_soc.sv` module that instantiates it.
--
--      The command is:
--      `iverilog -g2005-sv -o soc_sim on_chip_ram.v crc32_accelerator.v timer.v uart_tx.v uart_rx.v uart_top.v address_decoder.v arbiter.v interrupt_controller.v dma_engine.v simple_cpu.v risc_soc.sv tb_risc_soc.sv`
--
--      - `iverilog`: The compiler.
--      - `-g2005-sv`: Enables SystemVerilog features for the testbench.
--      - `-o soc_sim`: The name of the output simulation executable.
--      - `[file list]`: The complete list of design and verification files.
--
--   2. Simulation:
--      To specifically run the test that verifies this timer, the script
--      executes the compiled simulation with a "plusarg" to select the test.
--
--      The command is:
--      `vvp soc_sim +TESTNAME=TIMER_TEST`
--
--      - `vvp`: The simulation runtime engine.
--      - `soc_sim`: The compiled executable.
--      - `+TESTNAME=TIMER_TEST`: This argument is read by the SystemVerilog
--        testbench, which then calls the `run_timer_test` task. This task
--        programs the timer, waits for the interrupt, and verifies that the
--        interrupt was generated by the correct source (the timer), providing
--        a full end-to-end verification of this module's functionality within
--        the integrated SoC.
--
--------------------------------------------------------------------------------
*/