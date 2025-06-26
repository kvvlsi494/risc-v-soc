/*
--------------------------------------------------------------------------------
-- Module Name: uart_tx
-- Project: A Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: [Your Name/Persona]
--------------------------------------------------------------------------------
--
-- High-Level Module Purpose:
-- This module, `uart_tx`, implements the transmitter portion of a standard UART
-- (Universal Asynchronous Receiver-Transmitter). Its sole function is to take
-- an 8-bit parallel data byte written by the CPU and convert it into a serial
-- bitstream, framed with the necessary start and stop bits, and transmit it
-- one bit at a time on the `tx_pin` output.
--
-- Significance in the SoC Architecture:
-- The UART transmitter provides the SoC with a voice. It is the primary means
-- for the system to send human-readable debug information or status messages
-- to an external device, typically a host PC running a terminal program. The
-- logic is simpler than the receiver, as it controls the timing itself and does
-- not need to synchronize to an external signal. It provides a simple status
-- flag (`is_busy`) so the CPU knows when it is ready to accept a new character
-- for transmission.
--
-- Communication and Integration:
-- Like the receiver, this module is designed as a sub-component to be used
-- within the `uart_top` wrapper module.
--
--   - Receiving Commands from CPU (via `uart_top`): The CPU initiates a
--     transmission by writing an 8-bit byte to this module's data register via
--     the `uart_top` wrapper. It can also read a status register to check if
--     the transmitter is currently busy.
--
--   - Transmitting Serial Data: The module's primary output is the `tx_pin`,
--     which is routed through the `uart_top` wrapper to the top-level SoC pin.
--     This pin carries the final serialized data frame. In the project's main
--     test, this pin is looped back to the `uart_rx` module's input.
--
--------------------------------------------------------------------------------
*/

`timescale 1ns / 1ps


// This `module` declaration defines the boundary of the uart_tx block. It
// contains all the logic required to serialize a parallel byte into a
// standard asynchronous serial frame.
module uart_tx (

    // --- System Signals ---
    input clk,
    input rst_n,

    // --- Slave Bus Interface (via uart_top) ---
    input cs_n,
    input wr_en,
    input [1:0] addr,
    input [31:0] wdata,
    output [31:0] rdata,

    // --- Serial Data Output ---
    output tx_pin
    );
    

    // --- Timing and FSM State Parameters ---
    
    // `CLKS_PER_BIT`: A compile-time constant that defines the duration of one
    // serial bit in terms of system clock cycles. (e.g., 100MHz clk / 9600 Baud ~= 10417).
    parameter CLKS_PER_BIT = 10417;

    // These parameters provide readable names for the FSM state encodings.
    parameter S_IDLE = 3'b001; // Waiting for data from the CPU
    parameter S_TX_START_BIT = 3'b010; // Transmitting the '0' start bit
    parameter S_TX_DATA_BITS = 3'b011; // Transmitting the 8 data bits
    parameter S_TX_STOP_BIT = 3'b100; // Transmitting the '1' stop bit


    // --- Internal State and Data Registers ---
    
    // `state`: This 3-bit register holds the current state of the transmitter FSM.
    reg [2:0] state;

    // `clk_counter`: This register is a timer used to ensure each transmitted
    // bit is held for the correct duration defined by `CLKS_PER_BIT`.
    reg [13:0] clk_counter;

    // `bit_index`: This counter tracks which of the 8 data bits is currently
    // being transmitted.
    reg [3:0] bit_index;


    // `tx_data_reg`: An 8-bit register that latches the byte to be transmitted
    // from the CPU's `wdata` bus.
    reg [7:0] tx_data_reg;


    // `tx_pin_reg`: A single-bit register that directly drives the state of the
    // output `tx_pin`. The FSM updates this register with the correct bit value
    // (start, data, or stop) for each phase of the transmission.
    reg tx_pin_reg;


    // --- Internal Status Wire ---

    // `is_busy`: A combinational wire that provides status to the CPU. It is
    // '1' if the FSM is in any state other than IDLE, and '0' otherwise. This
    // tells the CPU whether the transmitter can accept a new byte.
    wire is_busy = (state != S_IDLE);


    // --- Combinational Read Logic for Status Register ---
    // This `assign` statement implements the read path for the CPU.
    // If a read is occurring (`!cs_n && !wr_en`) at the status register address
    // (`addr == 2'b01`), it outputs the value of the `is_busy` wire.
    // Otherwise, it drives high-impedance ('Z') to stay off the shared bus.
    assign rdata = (!cs_n && !wr_en && addr == 2'b01) ? {31'b0, is_busy} : 32'hZZZZZZZZ;


    // --- Combinational Output Pin Driver ---
    // This `assign` statement continuously connects the internal `tx_pin_reg`
    // to the module's top-level output port. The FSM controls `tx_pin_reg`,
    // and this line ensures that value is driven out of the chip.
    assign tx_pin = tx_pin_reg;


    // --- Main Transmitter FSM and Logic ---
    // This `always` block contains the entire state machine for the transmitter.
    // It is synchronous with an asynchronous reset.
    always @(posedge clk or negedge rst_n) begin


        // On reset, all state registers are cleared to their initial, idle values.
        // The `tx_pin_reg` is set to '1', representing the UART idle state.
        if (!rst_n) begin
            state <= S_IDLE; 
            tx_pin_reg <= 1'b1; 
            clk_counter <= 0;
            bit_index <= 0;
            tx_data_reg <= 0;
        end 
        

        // This `else` block contains the FSM's synchronous operation.
        else begin

            // The `case` statement implements the FSM logic based on the current `state`.
            case(state)

                // State S_IDLE: The transmitter is waiting for a byte from the CPU.
                S_IDLE: begin

                    // Keep the output line high (idle).
                    tx_pin_reg <= 1'b1;
                    
                    // Check if the CPU is writing to the data register (`addr == 2'b00`).
                    if (!cs_n && wr_en && addr == 2'b00) begin

                        // If so, latch the 8-bit data from the `wdata` bus.
                        tx_data_reg <= wdata[7:0];

                        // Reset the bit-timing counter.
                        clk_counter <= 0;

                        // Drive the `tx_pin` low to create the start bit.
                        tx_pin_reg <= 1'b0;

                        // Transition to the start bit transmission state.
                        state <= S_TX_START_BIT;
                    end
                end
                
                // State S_TX_START_BIT: Hold the line low for one full bit period.
                S_TX_START_BIT: begin

                    // If the bit period is not over, just increment the timer.
                    if (clk_counter < CLKS_PER_BIT-1) 
                    clk_counter <= clk_counter + 1;

                    // If the full bit period has elapsed...
                    else begin 

                        // ...reset the counters and prepare for the data bits.
                        clk_counter <= 0; 
                        bit_index <= 0;

                        // Transition to the data transmission state.
                        state <= S_TX_DATA_BITS; 
                    end
                end


                // State S_TX_DATA_BITS: Transmit the 8 data bits, one by one.
                S_TX_DATA_BITS: begin

                    // Drive the output pin with the current data bit, indexed by `bit_index`.
                    // This starts with bit 0 (the LSB).
                    tx_pin_reg <= tx_data_reg[bit_index];

                    // If the current bit's period is not over, increment the timer.
                    if (clk_counter < CLKS_PER_BIT-1) 
                    clk_counter <= clk_counter + 1;

                    // If the full bit period has elapsed...
                    else begin

                        // ...reset the timer for the next bit.
                        clk_counter <= 0;

                        // If this was the last data bit (bit 7)...
                        if (bit_index == 7)

                        // ...transition to the stop bit state.
                        state <= S_TX_STOP_BIT;

                        // Otherwise...
                        else

                        // ...increment the bit index to send the next bit.
                        bit_index <= bit_index + 1;

                    end

                end

                // State S_TX_STOP_BIT: Transmit the final stop bit.
                S_TX_STOP_BIT: begin

                    // Drive the output pin high for the stop bit.
                    tx_pin_reg <= 1'b1;

                    // Hold the line high for one full bit period.
                    if (clk_counter < CLKS_PER_BIT - 1) 
                    clk_counter <= clk_counter + 1;

                    // After the stop bit duration is complete...
                    else begin

                        // ...reset the timer and return to the idle state.
                        clk_counter <= 0;
                        state <= S_IDLE; 
                    end
                end
                

                // The `default` case ensures the FSM safely returns to IDLE if it
                // ever enters an illegal state.
                default:
                state <= S_IDLE;

            endcase

        end

    end

endmodule







/*
--------------------------------------------------------------------------------
-- Conceptual Deep Dive: UART Protocol (Transmitter Perspective)
--------------------------------------------------------------------------------
--
-- What is UART?
-- UART (Universal Asynchronous Receiver-Transmitter) is a simple serial protocol
-- that transmits data one bit at a time over a single wire. "Asynchronous"
-- means there is no separate clock signal sent along with the data. The
-- transmitter and receiver must agree on a "baud rate" (bits per second)
-- beforehand.
--
-- How does a transmitter construct a UART frame?
-- The transmitter's job is to take a parallel byte of data and meticulously
-- "draw" a specific voltage waveform on the `tx_pin` with precise timing. A
-- standard "8-N-1" (8 data bits, No parity, 1 stop bit) frame is constructed
-- by this module's FSM as follows:
--
--   1. Idle State (`S_IDLE`): Before and after transmission, the transmitter
--      must hold the `tx_pin` high ('1'). This is the default state.
--
--   2. Start Bit (`S_TX_START_BIT`): To signal the beginning of a frame, the FSM
--      pulls the `tx_pin` low ('0') for exactly one bit duration. The duration
--      is timed by the `clk_counter` counting up to `CLKS_PER_BIT`. A receiver
--      on the other end uses this falling edge to synchronize itself.
--
--   3. Data Bits (`S_TX_DATA_BITS`): Immediately following the start bit, the
--      FSM sends the 8 data bits from the `tx_data_reg`.
--      - Bit Order: It sends the Least Significant Bit (LSB, `tx_data_reg[0]`)
--        first and the Most Significant Bit (MSB, `tx_data_reg[7]`) last.
--      - Timing: The FSM uses the `clk_counter` to hold the `tx_pin` at the
--        correct level ('0' or '1') for each data bit for exactly one bit duration.
--
--   4. Stop Bit (`S_TX_STOP_BIT`): After the last data bit, the FSM pulls the
--      `tx_pin` back high ('1') for at least one bit duration. This definitively
--      marks the end of the frame and ensures the line returns to the idle
--      state, ready for the next transmission.
--
-- Where is this implemented?
-- The `always @(posedge clk)` block contains the FSM that perfectly executes
-- this sequence. Each `case` item in the FSM corresponds to one phase of the
-- frame construction, and the `clk_counter` is the master timer ensuring each
-- phase has the correct, standard-compliant duration.
--
--------------------------------------------------------------------------------
*/







/*
--
-- ############################################################################
-- ##                 Development Chronicle and Verification                 ##
-- ############################################################################
--
--
-- [[ Motive and Inception ]]
--
-- The motive for the `uart_tx` module was to provide the "output" half of a
-- complete communication channel. While the receiver allows the SoC to listen,
-- the transmitter gives it a voice. This is essential for printing debug
-- messages, status updates, or any form of data output to a host PC. My main
-- architectural goal was to build both the TX and RX modules so they could be
-- verified together in a "loopback" configuration, which is a powerful and
-- self-contained testing methodology.
--
--
-- [[ My Coding Ethic and Process ]]
--
-- The design process for the transmitter was very similar to the receiver, as
-- both are heavily FSM-driven:
--
--   1. FSM State Diagram: I started by drawing the state diagram, which is
--      simpler than the receiver's. The states were IDLE, TX_START, TX_DATA,
--      and TX_STOP. I mapped out the transitions and the actions to be taken
--      in each state (i.e., what value to drive on `tx_pin_reg`).
--
--   2. Timing Parameterization: The `CLKS_PER_BIT` parameter was defined first
--      to ensure the entire design was based on this configurable timing value,
--      making it flexible and readable.
--
--   3. FSM Implementation: I directly translated my state diagram into the Verilog
--      `case(state)` statement. Each `case` item represents a state, and the
--      logic within implements the actions and state transitions I had drawn.
--      Using parameters for state names (`S_IDLE`, etc.) was key to keeping the
--      code clean and understandable.
--
--   4. Clear Status Signal: I created the `is_busy` wire to provide a simple,
--      unambiguous status signal to the CPU. This is better practice than
--      forcing the CPU to infer the status from the FSM state itself.
--
--
-- [[ Unit Testing Strategy ]]
--
-- The unit test for the transmitter focused on verifying the correctness of the
-- output waveform.
--
--   - Dedicated Testbench: I created `tb_uart_tx.v` that instantiated only the
--     `uart_tx` module.
--
--   - Test Scenario: The testbench's main task was to act like the CPU, then
--     passively observe and check the output.
--       1. It would first check that the `tx_pin` was high (idle).
--       2. It would then simulate a CPU write, providing a known byte (e.g., 8'hD2)
--          to the DUT's data register.
--       3. The testbench would then enter a "monitor" mode.
--
--   - Self-Checking Scoreboard (Waveform Monitor): The testbench's scoreboard
--     was essentially a software-based UART receiver. It would:
--       1. Wait for a falling edge on `tx_pin` (the start bit).
--       2. Wait for a half-bit period, then sample to confirm the start bit was low.
--       3. Enter a loop, waiting for a full bit period and then sampling the
--          `tx_pin` 8 times, storing the results.
--       4. Wait one more bit period and check that the `tx_pin` was high (the stop bit).
--       5. Finally, it would compare the byte it re-assembled from the samples
--          against the original byte (`8'hD2`) and flag an error on any mismatch.
--
-- This unit test gave me high confidence that the transmitter was generating a
-- perfectly timed, standards-compliant serial frame before it was integrated.
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
-- Similar to the `uart_rx`, this `uart_tx` module is integrated hierarchically.
--
--   1. It is instantiated as `u_uart_tx` inside the `uart_top.v` wrapper module.
--   2. The `uart_top` module manages the bus interface, using address bit `addr[2]`
--      to ensure that CPU writes to the lower address range are directed to this
--      transmitter, while writes to the upper range go to the receiver.
--   3. The `tx_pin` output of this module is connected to the top-level `tx_pin`
--      of the `uart_top` wrapper, which is then connected to the SoC's main
--      `uart_tx_pin` output.
--
--   - System-Level Verification: Its functionality is primarily verified by the
--     `UART_LOOPBACK_TEST`. In this test, the CPU BFM writes a character to the
--     transmitter. The test then waits for the receiver to fire an interrupt and
--     checks if the received character matches the one that was sent. A "PASS"
--     in this test implicitly confirms that this transmitter correctly
--     serialized the data, as the receiver would not have gotten the correct
--     byte otherwise. This provides a robust, end-to-end verification of the
--     entire data path.
--
--
-- [[ Industrial Applications ]]
--
-- The UART transmitter is a fundamental IP block in the vast majority of SoCs,
-- primarily for low-to-medium speed serial output.
--
--   1. Debug Console: This is the most universal application. During chip
--      bring-up, debugging, and normal operation, embedded software uses the
--      UART transmitter to send status messages, logs, and diagnostic information
--      to a host PC's terminal. It is the hardware equivalent of a `printf`
--      statement and is often the first communication peripheral that is tested
--      on new silicon.
--
--   2. Control of External Modules: A main processor often uses a UART to send
--      commands to simpler, external peripherals. For example, sending AT
--      commands to a cellular modem, configuration data to a Bluetooth module,
--      or control packets to another microcontroller on the same board.
--
--   3. Data Logging: In sensor applications, an SoC might collect data, process
--      it, and then use a UART transmitter to stream the results to a data
--      logger or a PC for analysis.
--
--
-- [[ Industrially Relevant Insights Gained ]]
--
--   - Technical Insight: The importance of a clean FSM design. The behavior of
--     this module is entirely dependent on its state machine. Drawing the FSM
--     diagram first and then translating it directly into a Verilog `case`
--     statement was a critical process. It ensured that all states and
--     transitions were accounted for, and that the timing for each bit period
--     was precisely controlled by the `clk_counter`, resulting in a compliant
--     and predictable output waveform.
--
--   - Architectural Insight: Decoupling with a status signal. Instead of
--     requiring the CPU to know the internal state of the transmitter, I
--     provided a simple, one-bit `is_busy` status signal. The software contract
--     is simple: "Do not write a new character while `is_busy` is high." This
--     hides the internal complexity of the FSM from the software, providing a
--     clean hardware/software abstraction layer, which is a key principle of
--     good IP design.
--
--   - Non-Technical Insight: Modularity pays dividends. By designing the `uart_tx`
--     and `uart_rx` as two separate, self-contained modules, they become much
--     more reusable. If a future project needed only a transmitter or only a
--     receiver, the corresponding file could be used directly without modification.
--     This modular approach is standard practice in industry to build up a
--     library of reusable, verified IP blocks.
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
-- Bug Symptom: The most challenging bug was encountered during the unit test.
-- The testbench scoreboard, which was acting as a perfect receiver, reported
-- that the bits of the byte were being received in the wrong order. For example,
-- if I sent `8'b0100_0001` (the character 'A'), the scoreboard would receive
-- `8'b1000_0010`. The bits were correct, but they were reversed (MSB was sent first).
--
-- My Debugging Process:
--
--   1. Hypothesis: My indexing into the `tx_data_reg` was incorrect. I suspected
--      my `bit_index` counter was counting down from 7 instead of up from 0,
--      or that the logic `tx_pin_reg <= tx_data_reg[bit_index]` was somehow
--      accessing the wrong bit.
--
--   2. Evidence Gathering (Waveform Analysis): I opened GTKWave with the
--      failing unit test waveform. I added `tx_pin`, `state`, `tx_data_reg`,
--      and crucially, `bit_index` to the view.
--
--   3. The "Aha!" Moment: I sent the character 'A' (`8'b0100_0001`). In the
--      waveform, I saw the `tx_data_reg` correctly latch this value. I then
--      watched the FSM enter the `S_TX_DATA_BITS` state. I put my cursor on
--      the first data bit period. In the code, I expected to see `tx_pin_reg`
--      be assigned `tx_data_reg[0]`, which is '1'. However, the waveform showed
--      that `tx_pin` was driven to '0'. I looked at the value of `bit_index`
--      during that cycle and saw it was 0, as expected. The logic seemed right,
--      but the output was wrong. After staring at the code, I found the typo.
--      In an earlier version, my logic was `tx_pin_reg <= tx_data_reg[7-bit_index];`.
--      My brain had defaulted to a "count down" indexing scheme while the
--      `bit_index` counter itself was counting up. This mismatch caused the
--      MSB to be sent first.
--
-- The Fix: The fix was simple: I changed the line to `tx_pin_reg <= tx_data_reg[bit_index];`.
-- This ensured that as `bit_index` counted from 0 to 7, the hardware would
-- transmit bit 0, then bit 1, and so on, adhering to the LSB-first UART standard.
-- This was a classic lesson in being extremely careful with array indexing,
-- especially when dealing with bit-serial protocols.
--
--
-- [[ Current Limitations ]]
--
--   1. No Hardware FIFO: Similar to the receiver, the transmitter has only a
--      single-byte buffer (`tx_data_reg`). The CPU must poll the `is_busy`
--      status flag and wait for the entire previous byte to be transmitted
--      before it can write a new one. This is "blocking" and inefficient for
--      sending large amounts of data.
--   2. Fixed Configuration: The "8-N-1" frame format is hard-coded into the
--      FSM. It cannot be reconfigured by software to support other formats
--      (like 7 data bits or 2 stop bits).
--   3. No Interrupt Generation: This transmitter does not generate an interrupt
--      back to the CPU. The CPU has to poll to know when it's free. A more
--      advanced design would fire an interrupt like "Transmit Buffer Empty" to
--      signal the CPU that it can provide the next character.
--
--
-- [[ Future Improvements ]]
--
--   1. Add a Transmit FIFO: The most important upgrade would be to add a small
--      RAM-based FIFO. The CPU could then write a burst of several bytes into
--      the FIFO at once. The `uart_tx` FSM would then automatically pull bytes
--      from the FIFO and transmit them back-to-back until the FIFO is empty.
--      This would dramatically improve throughput for sending strings or data blocks.
--
--   2. Add a "TX Empty" Interrupt: I would add an interrupt output that fires
--      when the transmit FIFO becomes empty (or falls below a certain threshold).
--      This would allow for fully interrupt-driven transmit routines, freeing the
--      CPU from polling the busy status.
--
--   3. DMA Integration: A more advanced version could have a DMA request signal.
--      Instead of the CPU writing to the FIFO, the transmitter could directly
--      request data from a system DMA channel, allowing for high-speed, memory-
--      to-UART data streaming with zero CPU intervention.
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
-- The project was developed using a lightweight, open-source toolchain to
-- emphasize fundamental design skills over tool-specific knowledge.
--
--   - Coding Editor: Visual Studio Code (VS Code), chosen for its speed,
--     extensibility, and integrated terminal. The "Verilog-HDL/SystemVerilog"
--     extension was used for syntax highlighting and linting.
--
--   - Simulation Engine (EDA Tool): Icarus Verilog (`iverilog`). A free and
--     standards-compliant simulator that encourages writing portable and
--     high-quality RTL.
--
--   - Waveform Viewer: GTKWave. The standard companion to Icarus, essential for
--     debugging. For this `uart_tx` module, I used it in the unit test to
--     visually inspect the `tx_pin` waveform to ensure the start, data, and
--     stop bits had the correct values and, more importantly, the correct timing.
--
--   - Automation Scripting: Python 3. The `run_regression.py` script automates
--     the entire test flow, from compilation to result checking, using the
--     `subprocess` library.
--
--
-- [[ Execution Commands ]]
--
-- The `run_regression.py` script orchestrates the entire verification process,
-- generating the necessary shell commands to compile and simulate the design.
--
--   1. Compilation:
--      All Verilog and SystemVerilog design files are compiled into a single
--      executable. This `uart_tx.v` module must be compiled before the
--      `uart_top.v` wrapper that contains it.
--
--      The command is:
--      `iverilog -g2005-sv -o soc_sim on_chip_ram.v crc32_accelerator.v timer.v uart_tx.v uart_rx.v uart_top.v address_decoder.v arbiter.v interrupt_controller.v dma_engine.v simple_cpu.v risc_soc.sv tb_risc_soc.sv`
--
--      - `iverilog`: The compiler executable.
--      - `-g2005-sv`: Enables SystemVerilog features for the testbench.
--      - `-o soc_sim`: The name of the output simulation executable.
--      - `[file list]`: The full, ordered list of source files.
--
--   2. Simulation:
--      To verify this transmitter, the script runs the loopback test, which
--      implicitly validates its functionality.
--
--      The command is:
--      `vvp soc_sim +TESTNAME=UART_LOOPBACK_TEST`
--
--      - `vvp`: The simulation runtime engine.
--      - `soc_sim`: The compiled executable.
--      - `+TESTNAME=UART_LOOPBACK_TEST`: This argument directs the testbench
--        to run the `run_uart_loopback_test` task. This task writes a known byte
--        to this transmitter. The test only passes if the `uart_rx` module, which
--        is physically looped back to this module's output, correctly receives
--        the same byte. This end-to-end test confirms that the transmitter
--        generated a valid and correctly timed serial frame.
--
--------------------------------------------------------------------------------
*/


