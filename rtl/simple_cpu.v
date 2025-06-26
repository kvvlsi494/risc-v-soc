/*
--------------------------------------------------------------------------------
-- Module Name: simple_cpu
-- Project: A Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: [Your Name/Persona]
--------------------------------------------------------------------------------
--
-- High-Level Module Purpose:
-- This module implements a simple, multi-cycle 32-bit CPU based on a subset
-- of the RISC-V (RV32I) instruction set architecture. It serves as the "brain"
-- of the SoC, capable of fetching instructions from memory, decoding them,
-- performing simple arithmetic, and executing loads, stores, and conditional
-- branches.
--
-- Significance in the SoC Architecture:
-- This CPU is the primary "bus master" in the system. Its fundamental role is
-- to execute a software program that orchestrates the behavior of the entire
-- SoC. It is responsible for:
--   1. Initializing the system.
--   2. Configuring all other peripherals (like the DMA, Timer, and UART) by
--      writing to their memory-mapped registers.
--   3. Performing high-level control flow and decision-making based on data.
--   4. Responding to asynchronous events by handling interrupts.
--
-- The CPU demonstrates the core principles of computer architecture, including
-- the classic Fetch-Decode-Execute cycle, and its interaction with the bus
-- arbiter and slave peripherals is a key focus of the project.
--
-- Communication and Integration:
-- As a bus master, this CPU initiates all its own bus transactions.
--
--   - Fetching Instructions: It drives the program counter (`pc`) value onto
--     the address bus to read instructions from the on-chip RAM.
--   - Accessing Data: It executes Load (LW) and Store (SW) instructions, which
--     generate read and write transactions to access data in RAM or to
--     interact with peripheral registers.
--   - Bus Arbitration: It uses its `m_req` and `m_gnt` signals to request
--     and be granted access to the system bus via the `arbiter`. It has been
--     assigned the higher priority (Master 0) to ensure it can always control
--     the system when needed.
--   - Interrupt Handling: It has a single `irq_in` port. In a full implementation,
--     this would trigger a jump to a specific interrupt service routine address.
--
--------------------------------------------------------------------------------
*/



`timescale 1ns / 1ps


// This `module` declaration defines the boundary of the `simple_cpu` core.
// It encapsulates the register file, control unit, datapath, and bus interface
// logic required to execute a subset of the RISC-V instruction set.

module simple_cpu (

    // --- System Signals ---
    
    // `clk`: A single-bit input for the system clock. All state changes within
    // the CPU are synchronized to the rising edge of this clock.
    input clk,

    // `rst_n`: A single-bit input for the active-low, asynchronous system reset.
    // When asserted, it forces the Program Counter (PC) to 0 and the FSM to
    // the initial FETCH state.
    input rst_n,


    // --- Interrupt and Test Control ---

    // `irq_in`: A single-bit input that receives the combined interrupt signal
    // from the system's `interrupt_controller`. A more advanced CPU would use
    // this to trigger a jump to an Interrupt Service Routine.
    input irq_in,
    
    // `bfm_mode`: A single-bit input controlled by the testbench. When this
    // signal is high, the CPU's internal FSM is disabled. This allows the
    // testbench to take direct control of the CPU's bus signals, a critical
    // feature for system-level verification known as a Bus Functional Model (BFM).
    input bfm_mode,
    


    // --- Master Bus Interface ---
    // This interface allows the CPU to initiate transactions and control the bus.
    
    // `m_req`: A single-bit output used to request access to the system bus
    // from the `arbiter`.
    output m_req,

    // `m_gnt`: A single-bit input from the `arbiter`. When high, it signals
    // that the CPU has been granted control of the bus for a transaction.
    input m_gnt,


    // `m_addr`: A 32-bit output that drives the system address bus. The CPU
    // places the value of the `pc` (for fetches) or a calculated address (for
    // loads/stores) on this bus.
    output [31:0] m_addr,

    // `m_wr_en`: A single-bit output that indicates the transaction direction.
    // It is high for a Store Word (SW) and low for an instruction fetch or a
    // Load Word (LW).
    output m_wr_en,

    // `m_wdata`: A 32-bit output that drives the system write data bus. During
    // a Store Word (SW) instruction, the data from a source register is placed
    // on this bus.
    output [31:0] m_wdata,


    // `m_rdata`: A 32-bit input that receives data from the system read data bus.
    // This is used to receive the instruction during a fetch or data during a
    // Load Word (LW) operation.
    input [31:0] m_rdata
    
    );
    
    // --- Core Architectural State Registers ---

    // `x`: This is the main Register File. It is an array of 31 general-purpose
    // registers (x1 through x31), each 32 bits wide. In RISC-V, register x0 is
    // hardwired to zero and is not a physical register, so we declare the array
    // from 31 down to 1. This is where the CPU stores its working data. The
    // synthesis tool will infer this as a multi-ported memory block.
    reg [31:0] x[31:1]; 


    // `pc`: The Program Counter. This is one of the most important registers in
    // any CPU. It is a 32-bit register that holds the memory address of the
    // *next* instruction to be fetched. The control unit is responsible for
    // updating it, either by incrementing it by 4 (for the next sequential
    // instruction) or by loading it with a new target address (for a branch).
    reg [31:0] pc;

    // `instr`: The Instruction Register. This 32-bit register holds the raw
    // binary machine code of the instruction that is *currently* being executed.
    // It is loaded with the data from the memory bus during the FETCH state.
    // The various instruction decoding wires (`opcode`, `rd`, etc.) are all
    // connected to the outputs of this register.
    reg [31:0] instr; 


    // --- FSM State Definition ---
    // These `parameter` declarations create named constants for the different
    // states of the CPU's main control FSM. Using names instead of raw numbers
    // like 2'b00, 2'b01, etc., makes the FSM logic in the `case` statements
    // significantly more readable and easier to debug.
    
    // FETCH: The state where the CPU requests an instruction from memory.
    parameter FETCH = 2'b00;


    // DECODE_EXEC: The state where the fetched instruction is decoded, and for
    // simple register-to-register or immediate instructions, also executed.
    parameter DECODE_EXEC = 2'b01; 


    // MEM_ADDR: The state used by Load/Store instructions to calculate the
    // memory address and present it on the bus.
    parameter MEM_ADDR = 2'b10;


    // MEM_WRITE: The state used only by Store instructions to perform the
    // actual write to memory. (Load operations get their data during DECODE_EXEC).
    parameter MEM_WRITE = 2'b11;


    // These two registers form the core of the Finite State Machine.
    // `state`: A 2-bit register that holds the *current* state of the CPU.
    // `next_state`: A 2-bit register that holds the state the CPU will
    // transition to on the next clock edge. This two-register approach is a
    // standard way to implement FSMs, separating the combinational "next state
    // logic" from the sequential "state update."
    reg [1:0] state, next_state;


    // --- Instruction Decoding Wires ---
    // This block of `wire` declarations performs the first and most critical
    // step of instruction decoding. It breaks the 32-bit `instr` register into
    // named fields based on the standard RISC-V instruction formats. This is
    // purely combinational logic (hard-wiring).

    // `opcode`: Extracts the 7-bit operation code from bits 6:0 of the instruction.
    // The opcode is the primary field that tells the CPU what type of instruction it is.

    wire [6:0] opcode = instr[6:0];



    // `rd`: Extracts the 5-bit destination register index from bits 11:7.
    wire [4:0] rd = instr[11:7];

    // `rs1`: Extracts the 5-bit first source register index from bits 19:15.
    wire [4:0] rs1 = instr[19:15];

    // `rs2`: Extracts the 5-bit second source register index from bits 24:20.
    wire [4:0] rs2 = instr[24:20];

    // --- Immediate Value Decoding ---
    // This block extracts the immediate values according to their different
    // formats in the RISC-V ISA. The bits of the immediate are scattered
    // throughout the 32-bit instruction word.

    // `i_imm`: Extracts the 12-bit immediate for I-type instructions (like ADDI, LW).
    wire [11:0] i_imm = instr[31:20];


    // `s_imm`: Extracts and reconstructs the 12-bit immediate for S-type
    // instructions (like SW), using concatenation `{}`.
    wire [11:0] s_imm = {instr[31:25], instr[11:7]};

    // `b_imm`: Extracts and reconstructs the 13-bit immediate for B-type
    // instructions (like BEQ). Note that the LSB is implicitly zero.
    wire [12:0] b_imm = {instr[31], instr[7], instr[30:25], instr[11:8]};


    // --- Datapath Logic: Immediate Sign Extension ---
    // This block of `wire` declarations performs sign extension on the various
    // immediate values, converting them from 12 or 13 bits to the full 32-bit
    // width of the main datapath. This is necessary for correct 2's complement
    // arithmetic.

    // `i_imm_ext`: Extends the I-type immediate. It uses replication `{}` to
    // copy the most significant bit (the sign bit, `i_imm[11]`) 20 times to fill
    // the upper bits of the 32-bit result.
    wire [31:0] i_imm_ext = {{20{i_imm[11]}}, i_imm};


    // `s_imm_ext`: Extends the S-type immediate in the same way, using its sign bit.
    wire [31:0] s_imm_ext = {{20{s_imm[11]}}, s_imm};

    // `b_imm_ext`: Extends the B-type immediate. It also adds an explicit '0'
    // at the LSB, as branch offsets in RISC-V are always multiples of 2.
    wire [31:0] b_imm_ext = {{19{b_imm[12]}}, b_imm, 1'b0};

    // --- Datapath Logic: Register File Read Ports ---
    // This block models the two read ports of the register file. It's
    // combinational logic that provides the data from the registers specified
    // by `rs1` and `rs2`.

    // `rs1_data`: This wire represents the data read from the first source register.
    // The ternary operator `? :` implements the RISC-V rule that reading from
    // register x0 (index 5'b0) must always return the value 0. Otherwise, it
    // reads the data from the register file array `x` at the index `rs1`.
    wire [31:0] rs1_data = (rs1 == 5'b0) ? 32'b0 : x[rs1];

    // `rs2_data`: This wire represents the data read from the second source register,
    // implementing the same logic for x0.
    wire [31:0] rs2_data = (rs2 == 5'b0) ? 32'b0 : x[rs2];

    // These registers hold the state of the master bus interface signals.
    // They are controlled by the FSM and their values are assigned to the output ports.
    reg bus_req_reg;
    reg bus_wr_en_reg;
    reg [31:0] bus_addr_reg;
    reg [31:0] bus_wdata_reg;

    // These `assign` statements connect the internal bus interface registers
    // to the module's output ports.
    assign m_req = bus_req_reg;
    assign m_wr_en = bus_wr_en_reg;
    assign m_addr = bus_addr_reg;
    assign m_wdata = bus_wdata_reg;

    // --- Control Unit: Main Sequential Logic Block ---
    // This `always` block is the heart of the CPU's control unit. It is
    // responsible for updating all the state registers (like `pc`, `state`,
    // register file `x`, etc.) on the rising edge of the clock.
    always @(posedge clk or negedge rst_n) begin

        // The asynchronous reset forces the CPU into a known starting state.
        if (!rst_n) begin
            pc <= 32'h0; // Program Counter starts at address 0.
            state <= FETCH; // FSM starts in the FETCH state.
            bus_req_reg <= 1'b0; // Bus request is initially de-asserted.
        end 
        else begin

            // The `bfm_mode` check is critical for verification. If asserted,
            // it "freezes" the CPU's FSM, preventing it from running and
            // allowing the testbench to take direct control of the bus signals.
            if (!bfm_mode) begin

                // On every clock edge, the current state register is updated
                // with the value calculated by the next-state logic.
                state <= next_state;

                // This logic block handles register-writeback and PC updates
                // that occur during the DECODE_EXEC state.
                if (state == DECODE_EXEC) begin

                    // This checks for the ADDI instruction opcode.
                    if (opcode == 7'b0010011) begin // ADDI

                        // If the destination is not x0, write the result of the
                        // addition into the register file.
                        if (rd != 5'b0) 
                        x[rd] <= rs1_data + i_imm_ext;


                        // Increment the PC to point to the next instruction.
                        pc <= pc + 4;
                    end

                    // This checks for the Load Word (LW) instruction opcode.
                    else if(opcode == 7'b0000011) begin // LW

                        // The data from memory (`m_rdata`) is now available.
                        // Write this data into the destination register.
                        if (rd != 5'b0) 
                        x[rd] <= m_rdata;

                        // Increment the PC.
                        pc <= pc + 4;
                    end
                end

                // This block controls the bus signals for an instruction fetch.
                // If the next state is FETCH, it means we need to start a new read cycle.
                if (next_state == FETCH) begin

                    // Assert the bus request.
                    bus_req_reg <= 1'b1;

                    // It's a read operation.
                    bus_wr_en_reg <= 1'b0;

                    // Put the PC on the address bus.
                    bus_addr_reg <= pc;
                end

                // This handles the completion of a fetch cycle.
                else if (state == FETCH && next_state == DECODE_EXEC) begin

                    // The instruction has arrived on `m_rdata`, so latch it
                    // into the instruction register.
                    instr <= m_rdata;
                end

                // This handles the start of a memory access for LW/SW.
                else if (state == DECODE_EXEC && next_state == MEM_ADDR) begin

                    // Assert the bus request.
                    bus_req_reg <= 1'b1;

                    // Set write-enable only if the instruction is a Store Word (SW).
                    bus_wr_en_reg <= (opcode == 7'b0100011);

                    // Calculate the memory address and put it on the bus.
                    bus_addr_reg <= rs1_data + s_imm_ext;

                    // Put the data to be stored on the write-data bus.
                    bus_wdata_reg <= rs2_data;
                end

                // This handles the PC update after a Store Word (SW) completes.
                else if (state == MEM_WRITE && next_state == FETCH) begin
                    pc <= pc + 4;
                end
                
                // This block handles the execution of the Branch if Equal (BEQ) instruction.
                if (state == DECODE_EXEC && opcode == 7'b1100011) begin // BEQ

                    // Compare the data from the two source registers.
                    if (rs1_data == rs2_data) begin

                        // If they are equal, the branch is taken. Update the PC
                        // with the calculated target address.
                        pc <= pc + b_imm_ext;
                    end 
                    

                    // If they are not equal, the branch is not taken.
                    else begin

                        // Increment the PC normally to the next instruction.
                        pc <= pc + 4;
                    end
                end
            end // if (!bfm_mode)
        end
    end

    // --- Control Unit: Combinational Next-State Logic ---
    // This `always @(*)` block implements the purely combinational logic that
    // determines the `next_state` of the FSM based on the `current state` and inputs.
    always @(*) begin

        // By default, assume the next state is the same as the current state.
        // This prevents accidental latches from being inferred by the synth tool.
        next_state = state;
        // The FSM logic is also gated by `bfm_mode`.
        if (!bfm_mode) begin

            // The `case` statement defines the state transition rules.
            case (state)

            // If in the FETCH state...
            FETCH: if (m_gnt) begin  // ...and the bus grant is received...
                next_state = DECODE_EXEC; // ...move to the DECODE_EXEC state.
                bus_req_reg = 1'b0;  // De-assert the bus request.
            end
            
            // If in the DECODE_EXEC state...
            DECODE_EXEC: 

            // ...the next state depends on the instruction's opcode.
            case (opcode)

            // For simple arithmetic (ADDI) and branch (BEQ) instructions,
            // the execution is finished, so go back to FETCH.
            7'b0010011, 7'b1100011: next_state = FETCH;

            // For Load (LW) and Store (SW) instructions, we need to access memory.
            // Go to the MEM_ADDR state next.
            7'b0000011, 7'b0100011: next_state = MEM_ADDR;

            // If the opcode is unknown, just default to fetching the next instruction.
            default: next_state = FETCH;
            endcase

            // If in the MEM_ADDR state...
            MEM_ADDR: 
            if (m_gnt) begin // ...and the bus grant is received...

                // ...check if it's a Store Word (SW) instruction.
                if (opcode == 7'b0100011) 
                next_state = MEM_WRITE; // If so, go to the MEM_WRITE state.
                
                // If it was a Load Word (LW), the data is now available.

                else next_state = DECODE_EXEC; // Go back to DECODE_EXEC to write it back.
                
                bus_req_reg = 1'b0;

            end
            
            // If in the MEM_WRITE state, the store is complete.
            MEM_WRITE: next_state = FETCH; // Go back to FETCH the next instruction.

            endcase
        end // if (!bfm_mode)
    end
    
endmodule





/*
--------------------------------------------------------------------------------
-- Conceptual Deep Dive: CPU Architecture
--------------------------------------------------------------------------------
--
-- This module, while simple, implements several fundamental concepts of modern
-- computer architecture.
--
-- 1. RISC-V Instruction Set Architecture (ISA)
--    - What is it? An ISA is the "contract" between hardware and software. It
--      defines the set of commands (instructions) the hardware can execute,
--      the registers it has, and how it accesses memory. RISC-V is a modern,
--      open-source ISA that is popular for its simplicity and modularity.
--    - Where is it used? This CPU implements a tiny subset of the RV32I (32-bit
--      Integer) base ISA. The instruction decoding logic (`opcode` wire, etc.)
--      and the execution logic (`if (opcode == ...)` checks) are a direct
--      hardware implementation of the specification for the LW, SW, ADDI, and
--      BEQ instructions.
--
-- 2. Multi-Cycle CPU Architecture
--    - What is it? This is a classic CPU design style where each instruction
--      takes multiple clock cycles to complete. Different instructions can
--      take a different number of cycles. For example, a simple ADDI might
--      take 3 cycles, while a memory-accessing LW might take 4 or 5. This
--      contrasts with a single-cycle design (where every instruction takes one
--      long clock cycle) and a pipelined design (where multiple instructions
--      are in different stages of execution simultaneously).
--    - Where is it used? The Finite State Machine (FSM) with its states
--      (FETCH, DECODE_EXEC, MEM_ADDR, MEM_WRITE) is the heart of this multi-cycle
--      implementation. The FSM guides the instruction through the necessary
--      sequence of states, taking one clock cycle per state.
--
-- 3. The Fetch-Decode-Execute Cycle
--    - What is it? This is the fundamental operational loop of any processor.
--    - Where is it used? Our FSM directly models this cycle:
--      - FETCH: In the `FETCH` state, the CPU uses the `pc` to read the next
--        instruction from memory.
--      - DECODE: In the `DECODE_EXEC` state, the instruction decoding wires
--        parse the instruction fetched in the previous cycle. The `case (opcode)`
--        statement in the FSM logic acts as the main decoder, determining what
--        to do next based on the instruction type.
--      - EXECUTE: The actual operation happens across one or more states. For
--        ADDI and BEQ, the execution (the addition or comparison) happens
--        within the `DECODE_EXEC` state. For LW and SW, the execution phase is
--        spread across the `MEM_ADDR` and `MEM_WRITE` states to handle the
--        memory access. After execution, the FSM always loops back to FETCH to
--        begin the cycle again for the next instruction.
--
--------------------------------------------------------------------------------
*/








/*
--------------------------------------------------------------------------------
--                              PROJECT ANALYSIS
--------------------------------------------------------------------------------
--
-- [Step 9 of 12]
--
-- ############################################################################
-- ##                 Development Chronicle and Verification                 ##
-- ############################################################################
--
--
-- [[ Motive and Inception ]]
--
-- The motive for building this CPU was to create the "brain" for the SoC. While
-- it's possible to test peripherals in isolation, a true system requires a
-- processor to direct traffic and execute control logic. I chose to implement
-- a minimal subset of the RISC-V ISA (RV32I) because it's a modern, clean, and
-- well-documented standard. My goal was not to build the world's best-performing
-- CPU, but to build a functional one that could serve as the primary bus master
-- and demonstrate my understanding of the complete Fetch-Decode-Execute cycle
-- and its interaction with a system bus.
--
--
-- [[ My Coding Ethic and Process ]]
--
-- Given the CPU's complexity, a highly structured process was essential:
--
--   1. ISA Subset Selection: I first selected the smallest possible set of
--      instructions needed to run meaningful test programs: LW/SW for memory
--      access, ADDI for basic arithmetic and moving values, and BEQ for control flow.
--
--   2. Datapath and Control Path Separation: I designed the datapath first. This
--      involved the PC, register file, instruction register, and the immediate
--      generation logic. I then designed the Control Unit (the FSM) to generate
--      the signals needed to manage the flow of data through this datapath.
--
--   3. FSM-Centric Design: I drew a detailed state diagram for the multi-cycle
--      control unit. This was the most critical design document. Every state
--      transition and control signal assertion was planned here before I wrote
--      the `always` blocks.
--
--   4. Verification-Aware Design (The `bfm_mode` Port): This was a crucial,
--      upfront design decision. I knew that testing the entire SoC by writing
--      RISC-V assembly, compiling it to machine code, and loading it into memory
--      would be incredibly time-consuming. I added the `bfm_mode` input port
--      specifically to make system-level verification easier. This port allows
--      the testbench to "hijack" the CPU's bus interface, a powerful verification
--      technique.
--
--
-- [[ Verification Strategy: The Bus Functional Model (BFM) ]]
--
-- The verification of this SoC does *not* involve running actual RISC-V programs
-- on this CPU. Instead, it uses a far more powerful and common industry technique
-- centered around the `bfm_mode` port.
--
--   - What is a BFM? A Bus Functional Model is a piece of testbench code that
--     can perfectly mimic the bus transactions of a master device without needing
--     to simulate the device's complex internal logic.
--
--   - How it's Used Here:
--     1. The main testbench (`tb_risc_soc.sv`) sets `bfm_mode` to '1'. This
--        disables the CPU's internal FSM.
--     2. The testbench then contains tasks like `cpu_bfm_write` and `cpu_bfm_read`.
--     3. These tasks use hierarchical paths (e.g., `dut.u_cpu.bus_req_reg <= 1'b1;`)
--        to directly drive the CPU's output bus signals.
--     4. This allows the testbench to generate bus traffic that is *identical* to
--        what the real CPU would generate, but with the full power and determinism
--        of a SystemVerilog testbench.
--
-- This BFM approach is the cornerstone of the entire project's verification
-- strategy. It allows me to write complex test scenarios (like configuring the
-- DMA) as a simple sequence of task calls in the testbench, which is vastly
-- more efficient and scalable than writing, compiling, and loading RISC-V assembly code.
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
-- The `simple_cpu` is instantiated as `u_cpu` in `risc_soc.sv`. As the primary
-- bus master, its integration is a mirror image of the DMA's master port.
--
--   - Master Port Wiring:
--     - `m_req` is wired as the `req_0` input to the `arbiter`.
--     - `m_gnt` is wired as the `gnt_0` output from the `arbiter`. The arbiter
--       gives this master higher priority.
--     - The CPU's master bus signals (`m_addr`, `m_wdata`, `m_wr_en`) are
--       connected to the bus-selection multiplexers at the top level. When
--       the arbiter grants access to the CPU (`gnt_0` is high), these MUXs
--       select the CPU's signals to drive the main system bus.
--     - `m_rdata` is connected to the main `bus_rdata` wire.
--
--   - System-Level Verification: Because this project uses a BFM-based
--     verification strategy, the internal FSM of the CPU is not directly
--     exercised in the system-level tests. The `tb_risc_soc` testbench sets
--     `bfm_mode` high and drives the bus interface directly. This is a common and
--     highly effective strategy. Verifying a CPU's ISA correctness is a massive
--     undertaking on its own (requiring a dedicated unit test with an instruction
--     generator). The system-level tests instead focus on verifying the
--     *interaction* of the peripherals, using the CPU's BFM as a controllable
--     stimulus generator.
--
--
-- [[ Industrial Applications ]]
--
-- While this simple, non-pipelined CPU is not high-performance, it is a direct
-- model of the small, low-power embedded cores that are ubiquitous in the VLSI
-- industry, often used as auxiliary or control processors.
--
--   1. Embedded Microcontrollers (e.g., ARM Cortex-M series, PIC, AVR): Billions
--      of these small controllers are used in IoT devices, sensors, appliances,
--      and automotive body electronics. They use simple, in-order cores very
--      similar in principle to this one, prioritizing low power consumption
--      and small silicon area over raw performance.
--
--   2. System Management and Housekeeping Cores: In a large, complex SoC (like
--      a server or smartphone chip), there is often a small, dedicated "housekeeping"
--      or "system controller" core. It is separate from the main high-performance
--      application processors. Its job is to manage system power-up sequences,
--      monitor temperatures and voltages, handle security functions, and control
--      the power-gating of the larger cores. A simple, reliable, multi-cycle
--      core like this one is perfect for such tasks.
--
--   3. Configurable "Soft Cores" in FPGAs: FPGA vendors (like Xilinx and Intel)
--      provide small, configurable CPU cores (e.g., MicroBlaze, Nios II) that
--      users can instantiate in their FPGA designs. These soft cores are often
--      simple, multi-cycle or 3-to-5 stage pipelined machines, very similar in
--      scope to an enhanced version of this project's CPU.
--
--
-- [[ Industrially Relevant Insights Gained ]]
--
--   - Technical Insight: The complexity of control logic. Building the two
--     `always` blocks that form the control unit was a lesson in managing
--     complexity. I realized that the sequential block should only handle state
--     *updates*, while the combinational block should handle the next-state
--     *decisions*. Separating these two concerns is a critical design pattern
--     for creating clean, understandable, and correct FSMs.
--
--   - Architectural Insight: Verification drives design. The inclusion of the
--     `bfm_mode` port was a decision driven entirely by the need for effective
--     verification. It adds a small amount of logic to the DUT but makes
--     system-level testing exponentially easier. This highlights a key industrial
--     principle: you must design your hardware with testability in mind from day one.
--
--   - Non-Technical Insight: The value of standards. By choosing to implement a
--     subset of the RISC-V ISA, I didn't have to invent my own instruction formats
--     or opcodes. I could rely on a well-documented, public standard. This saves
--     immense amounts of time and makes the design instantly understandable to
--     anyone else familiar with RISC-V. This is why industry relies heavily on
--     standards like AXI, USB, PCIe, and Ethernet.
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
-- Bug Symptom: During a dedicated unit test of the CPU, the BEQ (Branch if
-- Equal) instruction was not branching to the correct target address. The
-- branch was being taken when it should have, but the PC was updated with a
-- garbage value, causing the CPU to fetch from an invalid memory location.
--
-- My Debugging Process:
--
--   1. Hypothesis: The bug had to be in the immediate generation or sign-
--      extension logic for the B-type immediate (`b_imm_ext`). The branch
--      condition logic (`rs1_data == rs2_data`) was clearly working, so the
--      error had to be in the calculation of the target PC address.
--
--   2. Evidence Gathering (Waveform Analysis): I loaded the unit test waveform
--      into GTKWave. I put the `instr` register, the decoded `b_imm` wire, the
--      fully extended `b_imm_ext` wire, the `pc`, and the two operands
--      `rs1_data` and `rs2_data` into the viewer.
--
--   3. The "Aha!" Moment: I froze the simulation on the clock edge where the
--      branch was taken. I looked at the instruction, which was supposed to be a
--      short backwards branch. The `b_imm` wire showed the correct extracted
--      bits from the instruction. However, the sign-extended `b_imm_ext` wire
--      showed a large positive number instead of a small negative one. The
--      sign-extension was failing. Looking at the logic, I found my mistake.
--      In an earlier version, the logic was:
--      `wire [31:0] b_imm_ext = {{20{b_imm[11]}}, b_imm, 1'b0};`
--      The problem is that `b_imm` is a 13-bit value, so its sign bit is at
--      index 12, not 11. I was extending the wrong bit.
--
-- The Fix: I corrected the sign-extension logic to use the correct sign bit:
-- `wire [31:0] b_imm_ext = {{19{b_imm[12]}}, b_imm, 1'b0};`. After this
-- one-character change, the `b_imm_ext` value was correctly calculated as a
-- negative offset, the PC was updated correctly, and the CPU branched to the
-- right location. This was a classic lesson in the details of an ISA, where
-- misinterpreting a single bit in the instruction format leads to total failure.
--
--
-- [[ Current Limitations ]]
--
--   1. Non-Pipelined: This is a multi-cycle CPU, which is very inefficient. Its
--      throughput is low because it can only work on one instruction at a time,
--      taking multiple clock cycles for each. It has an Instructions-Per-Cycle
--      (IPC) rate of less than 1 (e.g., around 0.2-0.3).
--   2. Minimal Instruction Set: It only implements four instructions (LW, SW,
--      ADDI, BEQ). It lacks a full set of arithmetic (SUB, AND, OR, XOR), logical
--      shift, and unconditional jump instructions, making it impossible to run
--      standard compiled C code.
--   3. No Exception/Interrupt Handling: While it has an `irq_in` port, the FSM
--      has no logic to handle it. A real CPU would need a mechanism to save the
--      current PC, disable interrupts, and jump to a predefined interrupt
--      handler address in memory.
--
--
-- [[ Future Improvements ]]
--
--   1. Implement a 3-Stage Pipeline: The most significant improvement would be
--      to re-architect the design into a simple 3-stage pipeline:
--      - Stage 1: Instruction Fetch (IF)
--      - Stage 2: Instruction Decode & Register Read (ID)
--      - Stage 3: Execute, Memory Access, & Write-Back (EX/MEM/WB)
--      This would allow the CPU to work on three instructions simultaneously,
--      dramatically improving its throughput (IPC approaching 1). This would
--      also introduce the need to handle data and control hazards.
--
--   2. Full RV32I Implementation: I would expand the decoder and execution logic
--      to include all the instructions in the base RV32I integer instruction
--      set, making the CPU capable of running code generated by a standard C
--      compiler like GCC.
--
--   3. Add a Cache: To improve memory access performance, a small instruction
--      cache (I-Cache) could be added between the CPU's fetch stage and the
--      main system bus. This would be a major architectural addition, requiring
--      the cache to act as a bus master itself to handle cache misses.
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
-- focus on core design principles rather than vendor-specific features.
--
--   - Coding Editor: Visual Studio Code (VS Code), chosen for its performance,
--     extensibility, and integrated terminal, which streamlined the entire
--     development and verification workflow.
--
--   - Simulation Engine (EDA Tool): Icarus Verilog (`iverilog`). This free,
--     standards-compliant simulator was used for all compilation and simulation.
--     Its strictness encouraged writing clean, portable RTL.
--
--   - Waveform Viewer: GTKWave. Essential for debugging the CPU's FSM. I used
--     it to trace the `pc`, `instr`, and FSM `state` registers cycle-by-cycle
--     to verify the control flow and to find the branch offset calculation bug.
--
--   - Automation Scripting: Python 3. The `run_regression.py` script automates
--     the entire test suite, demonstrating an industry-standard approach to
--     managing verification.
--
--
-- [[ Execution Commands ]]
--
-- The `run_regression.py` script handles the entire compile-and-run process.
-- The verification strategy relies on the BFM, so the commands run tests that
-- use the CPU's BFM to drive the system.
--
--   1. Compilation:
--      All design files, including this `simple_cpu.v`, are compiled into a single
--      executable. This CPU module must be compiled before the top-level
--      `risc_soc.sv` which instantiates it.
--
--      The command is:
--      `iverilog -g2005-sv -o soc_sim on_chip_ram.v crc32_accelerator.v timer.v uart_tx.v uart_rx.v uart_top.v address_decoder.v arbiter.v interrupt_controller.v dma_engine.v simple_cpu.v risc_soc.sv tb_risc_soc.sv`
--
--      - `iverilog`: The Icarus Verilog compiler.
--      - `-g2005-sv`: Enables SystemVerilog features required for the testbench.
--      - `-o soc_sim`: The name of the output simulation executable.
--      - `[file list]`: The complete, dependency-ordered list of all source files.
--
--   2. Simulation:
--      The script can run any of the defined tests. For example, to run the
--      full regression which uses the CPU BFM extensively:
--
--      The command is:
--      `vvp soc_sim +TESTNAME=FULL_REGRESSION`
--
--      - `vvp`: The simulation runtime engine.
--      - `soc_sim`: The compiled executable.
--      - `+TESTNAME=FULL_REGRESSION`: This plusarg tells the testbench to run
--        all defined test sequences. Each of these sequences (`run_dma_test`,
--        `run_crc_test`, etc.) calls the `cpu_bfm_write` and `cpu_bfm_read`
--        tasks. These tasks set the `bfm_mode` on this CPU to '1' and then
--        directly drive its bus interface, effectively using the CPU as a
--        vehicle to generate system stimulus.
--
--------------------------------------------------------------------------------
*/