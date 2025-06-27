// Copyright (c) 2025 Kumar Vedang
// SPDX-License-Identifier: MIT
//
// This source file is part of the RISC-V SoC project.
//


/*
--------------------------------------------------------------------------------
-- Module Name: uart_rx
-- Project: A Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: Kumar Vedang
--------------------------------------------------------------------------------
--
-- High-Level Module Purpose:
-- This module, `uart_rx`, implements the receiver portion of a standard UART
-- (Universal Asynchronous Receiver-Transmitter). Its primary function is to
-- "listen" to a single input pin (`rx_pin`), detect the start of an incoming
-- serial data frame, sample the data bits at the correct time, and assemble
-- them into a parallel 8-bit byte that the CPU can then read.
--
-- Significance in the SoC Architecture:
-- The UART receiver is the SoC's primary gateway for receiving data from the
-- "outside world" (e.g., a host PC, another microcontroller, or a sensor).
-- The logic is significantly more complex than the transmitter because it must
-- handle the asynchronous nature of the incoming data. It cannot rely on a
-- shared clock; instead, it must synchronize to the incoming bitstream by
-- detecting the start bit and then use its own internal, carefully timed
-- counters to sample the subsequent bits. It also provides an interrupt to the
-- CPU upon successful receipt of a byte, allowing for efficient, event-driven
-- communication.
--
-- Communication and Integration:
-- This module is designed to be a sub-component within a larger `uart_top`
-- wrapper. It is not intended to be instantiated directly in the main SoC file.
--
--   - Receiving Serial Data: Its `rx_pin` input is connected to the top-level
--     UART input pin of the SoC. In the `UART_LOOPBACK_TEST`, this is wired
--     directly to the `uart_tx` module's output.
--
--   - Interfacing with the CPU (via `uart_top`): It has a simple slave bus
--     interface that the `uart_top` module exposes to the main system bus.
--     The CPU can read from this module's data/status register to retrieve the
--     received byte and check if it's valid. A CPU write is used to acknowledge
--     receipt and clear the status, making the receiver ready for the next byte.
--
--   - Signaling an Event: Upon successfully receiving a full data frame (start
--     bit, 8 data bits, stop bit), it asserts its `irq_out` signal. The
--     `uart_top` wrapper passes this signal to the main `interrupt_controller`.
--
--------------------------------------------------------------------------------
*/



`timescale 1ns / 1ps


// This `module` declaration defines the boundary of the uart_rx block. It
// contains all the logic required to deserialize an incoming asynchronous
// bitstream into a parallel byte.
module uart_rx (

    // --- System Signals ---

    // `clk`: The main system clock input. The receiver's internal state
    // machine and counters are all synchronous to this clock.
    input clk,

    // `rst_n`: The active-low, asynchronous system reset. Used to force the
    // FSM and all registers into their initial, idle state.
    input rst_n,


    // --- Slave Bus Interface (via uart_top) ---
    // This interface allows the CPU to read the received data and status.

    // `cs_n`: The active-low chip select. This is driven by the `uart_top`
    // wrapper to enable this specific sub-module.
    input cs_n,


    // `wr_en`: The write enable signal. Used here for the CPU to acknowledge
    // receipt of data and clear the status flags.
    input wr_en,


    // `addr`: The 2-bit address bus from the `uart_top` wrapper, used to
    // select the data/status register within this module.
    input [1:0] addr,


    // `wdata`: The 32-bit write data bus. While not used to write data, its
    // associated write strobe is used to trigger the clearing of the status.
    input [31:0] wdata,


    // `rdata`: The 32-bit read data bus. This carries the received byte and
    // its validity status back to the CPU.
    output [31:0] rdata,


    // --- Serial Data and Status ---

    // `rx_pin`: This is the single-bit, physical input line that carries the
    // asynchronous serial data into the SoC.
    input rx_pin,


    // `irq_out`: A single-bit output that signals an interrupt request when a
    // new, valid byte has been successfully received.
    output irq_out
    );


    // --- Timing Parameter ---
    // This `parameter` is critical for the UART's operation. It defines the
    // number of system clock cycles that correspond to the duration of one bit
    // at the desired baud rate.
    // Calculation: (System Clock Frequency) / (Baud Rate)
    // Example: (100 MHz) / (9600 Baud) = 10416.66... ~= 10417
    // By making this a parameter, the same RTL code can be easily reconfigured
    // for different system clocks or baud rates without changing the logic.
    parameter CLKS_PER_BIT = 10417;


    // --- FSM State Parameters ---
    // These parameters give meaningful names to the states of the receiver's
    // Finite State Machine, which greatly improves code readability.

    parameter S_IDLE=3'd0; // Waiting for a start bit

    parameter S_START_BIT=3'd1; // Detected start bit, verifying it
    parameter S_RECEIVE_DATA=3'd2; // Actively sampling the 8 data bits
    parameter S_STOP_BIT=3'd3; // Waiting for and sampling the stop bit
    parameter S_CLEANUP=3'd4; // A byte is ready; waiting for CPU to read it


    // --- Internal State and Counter Registers ---

    // `state`: This 3-bit register holds the current state of the Finite State
    // Machine (FSM). The FSM is the brain of the receiver, and the value of this
    // register dictates all its actions.
    reg [2:0] state;

    // `clk_counter`: This register is a timing counter used to measure the
    // duration of each bit period. It increments on every system clock and is
    // reset when it reaches the value of `CLKS_PER_BIT`. Its width (14 bits)
    // is chosen to be large enough to hold the `CLKS_PER_BIT` value.
    reg [13:0] clk_counter;


    // `bit_index`: This small counter tracks which data bit (0 through 7) is
    // currently being received. It is used as the index for storing the sampled
    // bits into the `rx_data_reg` array.
    reg [2:0] bit_index;


    // `rx_data_reg`: This 8-bit register acts as a temporary buffer. As each
    // data bit is sampled from the `rx_pin`, it is stored in the corresponding
    // position of this register. When all 8 bits are received, this register
    // holds the complete parallel data byte.
    reg [7:0] rx_data_reg;


    // `data_valid_reg`: This single-bit register serves as a status flag for the
    // CPU. It is set to '1' only after a full, valid frame (including the stop
    // bit) has been received. The CPU reads this flag to know when the data in
    // `rx_data_reg` is ready. It also drives the `irq_out` signal.
    reg data_valid_reg;
    
    
    // --- Combinational Read Logic for Status/Data Register ---
    // This `assign` statement creates the read path for the CPU.
    // If a read is occurring (`!cs_n && !wr_en`) at the module's base address (`addr == 2'b00`),
    // it concatenates the status and data into a 32-bit word.
    //   - `data_valid_reg` is placed in bit 8.
    //   - `rx_data_reg` (the 8-bit received byte) is placed in bits 7:0.
    // Otherwise, it drives high-impedance ('Z').
    assign rdata = (!cs_n && !wr_en && addr == 2'b00) ? {23'b0, data_valid_reg, rx_data_reg} : 32'hZZZZZZZZ;


    // --- Combinational Interrupt Output ---
    // This `assign` statement directly wires the internal `data_valid_reg` flag
    // to the `irq_out` port. When a byte is valid, an interrupt is asserted.
    assign irq_out = data_valid_reg;


    // --- Main Receiver FSM and Logic ---
    // This `always` block contains the entire state machine for the receiver.
    // It is synchronous with an asynchronous reset.
    always @(posedge clk or negedge rst_n) begin

        // On reset, all state registers are cleared to their initial, idle values.
        if (!rst_n) begin
            state <= S_IDLE;
            clk_counter <= 0;
            bit_index <= 0;
            rx_data_reg <= 8'h00;
            data_valid_reg <= 1'b0;

        // This `else` block contains the FSM's synchronous operation.
        end else begin

            // The `case` statement implements the FSM logic based on the current `state`.
            case(state)

            // State S_IDLE: The receiver is waiting for communication to begin.
            S_IDLE:

            // It constantly monitors the `rx_pin` for a falling edge (1 to 0),
            // which signals the start of a start bit.
            if (rx_pin == 1'b0) begin 
                
                // When a start bit is detected, reset the bit-timing counter...
                clk_counter <= 0;

                // ...and transition to the start bit validation state.
                state <= S_START_BIT; 
            end


            // State S_START_BIT: The FSM has seen a potential start bit.
            S_START_BIT: begin

                // It waits for half a bit period to sample the line in the middle
                // of the start bit. This is a noise-rejection technique.
                if (clk_counter == (CLKS_PER_BIT/2)) begin

                    // If the line is still low, it's a valid start bit.
                    if (rx_pin == 1'b0) begin 

                        // Reset counters for the upcoming data bits...
                        clk_counter <= 0; 
                        bit_index <= 0;

                        // ...and transition to the data reception state.
                        state <= S_RECEIVE_DATA;
                    end
                    
                    // If the line went high, it was a glitch. Return to idle.
                    else state <= S_IDLE;
                    
                end 
                
                else clk_counter <= clk_counter + 1;
                    
            end
            

            // State S_RECEIVE_DATA: The FSM samples the 8 data bits.
            S_RECEIVE_DATA: begin
                
                // It waits for one full bit period to pass.
                if (clk_counter == CLKS_PER_BIT-1) begin

                    // Reset the bit-timing counter for the next bit.
                    clk_counter <= 0;

                    // Sample the `rx_pin` and store the value in the `rx_data_reg`
                    // at the position indicated by the `bit_index`.
                    rx_data_reg[bit_index] <= rx_pin;

                    // If there are more bits to receive...
                    if (bit_index < 7)

                    // ...increment the bit index.
                    bit_index <= bit_index + 1;
                    
                    // If this was the last data bit (bit 7)...
                    else 

                    // ...transition to the stop bit state.
                    state <= S_STOP_BIT;
                end 
                
                else clk_counter <= clk_counter + 1;

            end
            
            // State S_STOP_BIT: All 8 data bits have been received.
            S_STOP_BIT: begin

                // It waits one more full bit period.
                if (clk_counter == CLKS_PER_BIT-1) begin

                    // At the end, it samples the line, expecting a '1' for a
                    // valid stop bit.
                    if (rx_pin == 1'b1) 
                    // If the stop bit is valid, set the `data_valid_reg` flag.
                    data_valid_reg <= 1'b1;

                    // Transition to the cleanup state, regardless of whether the
                    // stop bit was valid (error checking could be added here).
                    state <= S_CLEANUP;
                end 
                
                else clk_counter <= clk_counter + 1;
            end

            // State S_CLEANUP: A byte is ready and waiting for the CPU to read it.
            S_CLEANUP: begin

                // The FSM will wait in this state indefinitely until the CPU
                // performs a write to this module's base address.
                if (!cs_n && wr_en && addr == 2'b00) begin

                    // This write acts as an acknowledgement, clearing the valid flag...
                    data_valid_reg <= 1'b0;

                    // ...and returning the FSM to the idle state to wait for the next byte.
                    state <= S_IDLE;
                end
            end
            
            // The `default` case ensures that if the FSM somehow enters an
            // invalid state, it will safely return to idle.
            default: state <= S_IDLE;
            
            endcase
            
        end
    end
endmodule







/*
--------------------------------------------------------------------------------
-- Conceptual Deep Dive: UART Protocol (Receiver Perspective)
--------------------------------------------------------------------------------
--
-- What is UART?
-- UART (Universal Asynchronous Receiver-Transmitter) is one of the oldest and
-- simplest serial communication protocols. "Asynchronous" is the key word:
-- there is no shared clock line between the transmitter and receiver. The
-- receiver must synchronize itself to the incoming data stream on the fly.
--
-- A standard UART data frame consists of:
--   - Idle State: The line is held high ('1').
--   - Start Bit: A single bit where the line is pulled low ('0'). This signals
--     the start of a new frame and is used for synchronization.
--   - Data Bits: Typically 5 to 8 data bits, sent sequentially (usually LSB first).
--   - Parity Bit (Optional): An extra bit for simple error checking. This design
--     does not implement parity.
--   - Stop Bit(s): One or two bits where the line is pulled high ('1') to signal
--     the end of the frame and provide a buffer before the next one.
--
-- Where is the concept used in this file?
-- This entire module is a hardware FSM designed to parse this exact frame format.
--
--   1. Synchronization (`S_IDLE` -> `S_START_BIT`): The FSM waits in `S_IDLE`
--      for the falling edge on `rx_pin`. This is the synchronization event.
--
--   2. Oversampling and Noise Rejection (`S_START_BIT`): The biggest challenge for a
--      receiver is knowing *when* to sample each bit. Since the transmitter and
--      receiver clocks are not perfectly aligned, sampling at the very edge of a
--      bit period is risky. The standard technique is to sample in the middle of
--      the bit period. This FSM achieves this by waiting for half a bit period
--      (`CLKS_PER_BIT/2`) after detecting the start bit edge. It re-checks if the
--      line is still low. This confirms it wasn't just a short noise glitch and
--      aligns the sampling point to the middle of the start bit.
--
--   3. Data Sampling (`S_RECEIVE_DATA`): After synchronizing on the start bit,
--      the FSM enters a loop. It uses the `clk_counter` to wait for one full
--      bit period (`CLKS_PER_BIT-1`). This positions its sampling point in the
--      middle of the next data bit. It samples the `rx_pin`, stores the value,
--      and repeats this for all 8 data bits.
--
--   4. Frame Validation (`S_STOP_BIT`): After the last data bit, the FSM waits
--      one more bit period and checks for the stop bit (a high signal). Finding
--      a '1' here gives confidence that the frame was received correctly and
--      wasn't corrupted or misaligned.
--
-- Why is this used?
-- This FSM-based approach is the standard hardware method for implementing a
-- robust UART receiver. It solves the core problem of asynchronous communication
-- by using the start bit as a trigger to start its own internal, precise timers,
-- ensuring that data is sampled reliably at the center of each bit period, where
-- the signal is most stable.
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
-- The motive for creating the `uart_rx` and its `uart_tx` counterpart was to
-- provide a basic, human-readable communication interface for the SoC. While
-- the other peripherals (DMA, CRC, Timer) are essential for internal data
-- processing, the UART is the bridge to the outside world. It allows the SoC
-- to send debug messages to a host computer's terminal or to receive commands.
-- I specifically wanted to build both halves to create a self-contained
-- "loopback" test, which is a powerful way to verify a communication peripheral
-- without needing external hardware.
--
--
-- [[ My Coding Ethic and Process ]]
--
-- The logic for the receiver is entirely dictated by its FSM, so my process was
-- heavily FSM-centric:
--
--   1. FSM State Diagram: Before any code was written, I drew the state diagram
--      on paper. I defined the states (IDLE, START_BIT, RECEIVE_DATA, STOP_BIT,
--      CLEANUP) and, most importantly, the exact timing conditions for
--      transitioning between them. This diagram was my single source of truth.
--
--   2. Parameterization of Timing: I knew the timing was critical. Instead of
--      hard-coding a number like `10417`, I immediately created the
--      `CLKS_PER_BIT` parameter. This makes the design reusable and easy to
--      retarget for different clock speeds or baud rates.
--
--   3. FSM Implementation: I translated the state diagram directly into the
--      `case(state)` statement. Each `case` item corresponds to a state bubble
--      in my diagram, and the `if` conditions inside it correspond to the
--      transition arrows.
--
--   4. Mid-point Sampling: I explicitly implemented the logic to sample the
--      start bit in the middle of its period (`CLKS_PER_BIT/2`). This is a
--      standard, robust technique for noise immunity that I wanted to ensure was
--      part of the design from the beginning.
--
--
-- [[ Unit Testing Strategy ]]
--
-- The unit test for the receiver was one of the most interesting to write, as
-- the testbench's primary job was to "draw" a precisely timed serial waveform
-- for the DUT to consume.
--
--   - Dedicated Testbench: I created a `tb_uart_rx.v` file. This testbench
--     instantiated only the `uart_rx` module.
--
--   - Waveform Generation Task: The core of the testbench was a task called
--     `send_serial_byte(input [7:0] byte_to_send)`. This task would:
--       1. Drive the `rx_pin` high (idle).
--       2. Wait for some time.
--       3. Drive `rx_pin` low for exactly `CLKS_PER_BIT` cycles (the start bit).
--       4. Loop 8 times, driving the `rx_pin` with each bit of `byte_to_send`
--          (LSB first), holding each value for `CLKS_PER_BIT` cycles.
--       5. Drive `rx_pin` high for `CLKS_PER_BIT` cycles (the stop bit).
--
--   - Self-Checking Scoreboard: The test would call this task with a known byte
--     (e.g., `8'hA5`). It would then wait for the DUT's `irq_out` to go high.
--     Once the interrupt was asserted, the testbench would simulate a CPU read
--     of the DUT's `rdata` port. It would then check that the `data_valid` flag
--     was set and that the received byte matched the one it sent. It also tested
--     negative conditions, like sending a frame with a faulty (low) stop bit,
--     and verified that the `data_valid` flag did *not* get set.
--
--------------------------------------------------------------------------------
*/







/*
--
-- ############################################################################
-- ##                   System Integration and Verification                  ##
-- ############################################################################
--
--
-- [[ Integration into the Top-Level SoC ]]
--
-- This `uart_rx` module follows a hierarchical design pattern. It is not
-- instantiated directly in the top-level `risc_soc.sv` file. Instead:
--
--   1. It is instantiated as `u_uart_rx` inside the `uart_top.v` wrapper module.
--   2. The `uart_top` module acts as a "manager" or facade for both the
--      transmitter and receiver. It handles the address decoding logic that
--      directs CPU bus accesses to either the `uart_tx` or this `uart_rx`
--      sub-module.
--   3. Within `uart_top`, the `rx_pin` of this module is connected to the top-level
--      `rx_pin` of the `uart_top` wrapper.
--   4. The `irq_out` of this module is connected to the `irq_out` of the
--      `uart_top` wrapper, which is then connected to the main system
--      `interrupt_controller`.
--
-- This hierarchical approach is a clean design practice, as it groups the
-- related TX and RX logic into a single, cohesive UART peripheral from the
-- perspective of the main SoC.
--
--
-- [[ System-Level Verification Strategy ]]
--
-- The primary system-level test for the UART is the `UART_LOOPBACK_TEST`,
-- defined in `tb_risc_soc.sv`. This is a powerful, self-contained test that
-- verifies both the transmitter and receiver simultaneously without needing
-- an external device.
--
--   - The Loopback Connection: In the top-level testbench (`tb_risc_soc`), the
--     output pin from the DUT's UART (`uart_tx_pin_from_dut`) is directly wired
--     to the input pin (`uart_rx_pin_to_dut`). This creates a physical loopback.
--
--   - Test Flow:
--     1. The testbench, using the CPU BFM, writes a known character (e.g., 8'hE7)
--        to the `uart_tx` data register.
--     2. The `uart_tx` module serializes this byte and transmits it on the
--        `uart_tx_pin_from_dut`.
--     3. Because of the loopback, this serial bitstream is immediately received
--        on the `uart_rx_pin_to_dut` and processed by this `uart_rx` module.
--     4. The testbench then waits for the receiver to assert its interrupt
--        (`wait (dut.cpu_irq_in == 1'b1);`).
--
--   - Scoreboard Checks:
--     1. Once the interrupt fires, the scoreboard reads the `interrupt_controller`
--        status register to confirm that the interrupt came from the UART source.
--     2. It then reads the `uart_rx` data/status register.
--     3. It verifies two things: that the `data_valid` flag is set, and that the
--        received byte (`rdata[7:0]`) is equal to the original character (`8'hE7`).
--
-- A "PASS" in this test provides end-to-end verification of the entire UART
-- subsystem, proving that the transmitter, receiver, wrapper logic, and
-- interrupt pathway are all working together correctly.
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
-- The UART is a foundational serial interface, and virtually every SoC, from
-- the smallest microcontroller to the largest server-grade chip, includes one
-- or more. Its simplicity and low pin count make it indispensable.
--
--   1. System Debug and Console Access: This is the most common use case in
--      the industry. During chip bring-up and validation, a UART interface is
--      the primary way for engineers to get a "console" on the embedded CPU.
--      Bootloaders and low-level diagnostic software print status messages
--      (like "Booting...", "Memory test PASSED") to the UART, which are viewed
--      on a host PC's terminal. It's the "printf" of the hardware world.
--
--   2. Inter-chip Communication: UART is often used for low-to-medium speed
--      communication between different chips on a PCB. A main application
--      processor might use its UART to configure or get data from external
--      modules like:
--      - GPS Modules: These typically stream location data (NMEA sentences)
--        over a UART interface.
--      - Bluetooth/Wi-Fi Modules: Low-level configuration and control commands
--        are often sent over a UART using a standardized protocol like HCI.
--      - Sensors and other Microcontrollers.
--
--   3. Legacy Interfaces: The RS-232, RS-422, and RS-485 standards, still
--      widely used in industrial control, automation, and point-of-sale
--      systems, are all built on the fundamental UART communication protocol.
--      SoCs designed for these markets must include robust UART peripherals.
--
--
-- [[ Industrially Relevant Insights Gained ]]
--
-- Building the receiver half of the UART was particularly insightful because
-- of the asynchronous timing challenges.
--
--   - Technical Insight: The importance of robust synchronization and sampling.
--     The logic in the `S_START_BIT` state, which waits for half a bit period
--     before re-checking the line, is a crucial technique for noise immunity.
--     A simple glitch could cause the FSM to trigger, but by sampling again
--     in the middle of the bit, the design confirms it's a legitimate start
--     bit. This concept of "oversampling" to find the stable center of a signal
--     is a core technique used in all high-speed serial receivers (like those
--     for PCIe or USB), albeit in a much more complex form.
--
--   - Design-for-Verification Insight: The loopback test is a powerful pattern.
--     Designing both the TX and RX modules allowed me to create a fully
--     self-contained test that didn't rely on any external stimulus. In the
--     industry, this is a common and highly valued feature. An IP block that
--     has a built-in "internal loopback" mode is much easier and faster for
--     validation teams to test, as it reduces dependencies on external hardware
--     or complex bus functional models.
--
--   - Non-Technical Insight: Appreciating legacy protocols. While modern
--     protocols are much faster and more complex, there is a reason UART
--     persists: it's simple, it's robust, and it just works. It requires minimal
--     hardware and software overhead. This project taught me that sometimes the
--     "old" or "simple" solution is still the best engineering choice for a
--     given problem, especially for cost-sensitive or low-level applications
--     like a debug console.
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
-- Bug Symptom: The `UART_LOOPBACK_TEST` was consistently failing. The testbench
-- would send a byte like `8'h55` (binary 01010101), but the receiver would
-- report getting a corrupted, shifted value like `8'hAA` (binary 10101010) or
-- garbage. The error was consistent, not random, which pointed to a systemic
-- timing or logic error in the FSM.
--
-- My Debugging Process:
--
--   1. Hypothesis: My initial thought was that the `clk_counter` logic was
--      flawed. I suspected it wasn't waiting for the full `CLKS_PER_BIT` period,
--      causing me to sample the incoming bits at the wrong time (e.g., too early
--      or too late), leading to bit shifting.
--
--   2. Evidence Gathering (Waveform Analysis): I opened GTKWave and loaded the
--      waveform from the failing loopback test. This was the ultimate source
--      of truth. I added the following key signals:
--      - The transmitted waveform: `dut.u_uart.u_uart_tx.tx_pin`
--      - The FSM state of the receiver: `dut.u_uart.u_uart_rx.state`
--      - The receiver's internal counters: `clk_counter` and `bit_index`
--      - The receiver's buffered data: `rx_data_reg`
--
--   3. The "Aha!" Moment: I aligned the `tx_pin` waveform with the receiver's
--      internal states. I saw the transmitter correctly sending the start bit.
--      I saw my receiver FSM correctly transition from `S_IDLE` to `S_START_BIT`
--      and then to `S_RECEIVE_DATA`. The problem was visible when I looked at the
--      `clk_counter` in the `S_RECEIVE_DATA` state. I had an off-by-one error
--      in my condition: `if (clk_counter == CLKS_PER_BIT)`. Because the counter
--      starts from 0, it should count up to `CLKS_PER_BIT - 1` to represent a
--      full period. My condition meant it was waiting one clock cycle too long
--      for every single bit. This caused the sampling point to drift further
--      and further into the *next* bit's period with each successive bit,
--      completely corrupting the received byte.
--
-- The Fix: The fix was a simple one-character change in the FSM logic: I
-- corrected the condition to be `if (clk_counter == CLKS_PER_BIT - 1)`. After
-- this change, the waveform clearly showed the `rx_pin` being sampled exactly
-- in the middle of each bit period, and the test passed immediately. This bug
-- was a powerful lesson in the importance of precise "off-by-one" checking in
-- any timing-critical FSM.
--
--
-- [[ Current Limitations ]]
--
--   1. No Hardware FIFO: This receiver has only a single-byte buffer (`rx_data_reg`).
--      If a second byte arrives on the `rx_pin` before the CPU has had a chance
--      to read the first one, the first byte will be overwritten and lost. This
--      is known as a "receiver overrun" error.
--   2. No Parity or Error Checking: The design does not implement a parity bit
--      for basic error detection. It also has very simple framing error detection
--      (it only checks if the stop bit is high), but it doesn't flag this error
--      to the CPU in any way.
--   3. Fixed Configuration: The configuration (8 data bits, no parity, 1 stop
--      bit, or "8-N-1") is hard-coded in the FSM logic. A more versatile UART
--      would allow the CPU to configure these parameters.
--
--
-- [[ Future Improvements ]]
--
--   1. Add a Receive FIFO: This is the most important improvement. I would place
--      a small, RAM-based FIFO buffer (e.g., 16 bytes deep) between the serial
--      deserializer logic and the CPU interface. The FSM would write received
--      bytes into the FIFO. This would allow the receiver to buffer multiple
--      incoming bytes, giving the CPU much more time to service the interrupt
--      and read the data without losing any, making the system far more robust.
--
--   2. Implement Full Error Detection: I would add logic to detect parity
--      errors (if enabled) and framing errors (if the stop bit is not high).
--      These error conditions would be reported as status bits in the `rdata`
--      register, allowing the CPU software to know that a received byte was
--      corrupted and should be discarded.
--
--   3. Create a Configurable Datapath: I would add a main Control Register that
--      the CPU could program to select different modes, such as 7 vs. 8 data
--      bits, or to enable/disable parity checking. This would make the UART IP
--      much more flexible and reusable.
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
-- This project was built using a lean, open-source toolchain to ensure that
-- the focus remained on solid digital design principles rather than vendor-
-- specific tool features.
--
--   - Coding Editor: Visual Studio Code (VS Code). I used VS Code for its
--     responsive interface and powerful "Verilog-HDL/SystemVerilog" extension,
--     which provided the syntax highlighting and real-time linting necessary
--     for efficient RTL development.
--
--   - Simulation Engine (EDA Tool): Icarus Verilog (`iverilog`). This is a
--     well-established, free, and standards-compliant Verilog simulator. Its
--     strictness helped enforce good coding practices.
--
--   - Waveform Viewer: GTKWave. This tool was indispensable for debugging the
--     FSM timing of this `uart_rx` module. Being able to visualize the `rx_pin`
--     waveform against the internal `state` and `clk_counter` registers was the
--     only way to find the subtle off-by-one timing bug in the sampling logic.
--
--   - Automation Scripting: Python 3. The `run_regression.py` script leverages
--     Python's standard libraries to automate the entire test process, from
--     compilation to log file parsing, which is a common practice in the industry.
--
--
-- [[ Execution Commands ]]
--
-- The `run_regression.py` script is the single entry point for running the
-- entire verification suite. It generates the necessary shell commands.
--
--   1. Compilation:
--      All Verilog and SystemVerilog files are compiled into one executable.
--      This `uart_rx.v` file is compiled before the `uart_top.v` wrapper that
--      instantiates it.
--
--      The command is:
--      `iverilog -g2005-sv -o soc_sim on_chip_ram.v crc32_accelerator.v timer.v uart_tx.v uart_rx.v uart_top.v address_decoder.v arbiter.v interrupt_controller.v dma_engine.v simple_cpu.v risc_soc.sv tb_risc_soc.sv`
--
--      - `iverilog`: The compiler.
--      - `-g2005-sv`: Enables SystemVerilog features (for the testbench).
--      - `-o soc_sim`: Specifies the name of the output executable.
--      - `[file list]`: The complete, ordered list of all source files.
--
--   2. Simulation:
--      To specifically test the UART functionality, including this receiver,
--      the script runs the simulation with the appropriate plusarg.
--
--      The command is:
--      `vvp soc_sim +TESTNAME=UART_LOOPBACK_TEST`
--
--      - `vvp`: The simulation runtime engine.
--      - `soc_sim`: The compiled executable.
--      - `+TESTNAME=UART_LOOPBACK_TEST`: This argument tells the testbench to
--        run the specific loopback test. This test verifies the `uart_rx`
--        module by having the `uart_tx` module transmit a known byte, which is
--        physically looped back to the `rx_pin` in the testbench. The test
--        passes only if this receiver correctly deserializes the byte and
--        asserts a valid data interrupt.
--
--------------------------------------------------------------------------------
*/