# Verification Strategy & Results

## 1. Verification Philosophy

The verification strategy for this project is built on the industry-standard principle that **verification should consume more effort than design**. The goal is not just to show that the design works ("positive testing"), but to actively try to break it by testing corner cases and complex interactions ("negative testing"). The entire environment is **automated** and **self-checking**.

## 2. The UVM-like Testbench Architecture

The system-level testbench (`tb/tb_risc_soc.sv`) is architected using principles from the Universal Verification Methodology (UVM) to create a scalable and layered environment.

- **Bus Functional Model (BFM):** The testbench does not require writing RISC-V assembly. Instead, it uses a BFM to directly control the CPU's bus interface. The `bfm_mode` port on the `simple_cpu` allows the testbench to disable the CPU's FSM and drive its bus signals. This provides precise, repeatable, and powerful stimulus generation.

- **Layered Tests (Sequences):** High-level tasks like `run_dma_test` act as sequences. They define a complete transaction (e.g., "configure the DMA, start it, wait for an interrupt") by calling a series of lower-level BFM tasks.

- **Self-Checking Scoreboards:** Every test is self-checking. After a transaction, scoreboard logic within the test automatically validates the result against a golden model. For example, the DMA test reads back the destination memory and compares it against the source, while the CRC test calculates the expected CRC in software and compares it against the hardware result. A test only passes if the scoreboard reports a match.

## 3. Waveform Analysis: Debugging a DMA Data Corruption Bug

One of the most critical bugs found during development was a data corruption issue in the DMA engine. The scoreboard reported that the data being written was stale or all zeros. This is a classic example of how waveform analysis is used to find the root cause.

#### The Symptom
The DMA transfer would "complete," but the data in the destination memory was incorrect.

#### The Waveform
The key was to analyze the relationship between the DMA's FSM state, its master bus signals, and the system's read data bus.


*(Note: This is a representative image. In a real project, you would insert a screenshot of your actual GTKWave session here.)*

#### In-Depth Waveform Interpretation

1.  **(Marker A) `S_READ_ADDR` State:** The waveform shows the DMA FSM (`u_dma.state`) entering the `S_READ_ADDR` state. In this cycle, the DMA correctly drives the source address (`0x1000`) onto its master address bus (`u_dma.m_addr`). It asserts `m_req`, and the arbiter grants the bus.

2.  **(Marker B) RAM Response:** One clock cycle later, the `on_chip_ram` responds to the read request. The correct data (`0xCAFE0001`) appears on the main system read data bus (`bus_rdata`). **This is the critical observation: the data is only valid for this one cycle.**

3.  **(Marker C) The Flaw:** In the original, buggy design, the FSM would transition directly from `S_READ_ADDR` to `S_WRITE_ADDR`. By the time it tried to sample the data in the `S_WRITE_ADDR` state, `bus_rdata` was no longer being driven by the RAM, and the DMA's internal `data_buffer` would latch an invalid (stale or 'X') value.

4.  **The Fix in the Waveform:** The corrected waveform (as shown) includes the new **`S_READ_WAIT`** state. The FSM transitions from `S_READ_ADDR` to `S_READ_WAIT`. During this state (between Marker B and C), the `bus_rdata` is stable. At the end of the `S_READ_WAIT` state, the DMA latches this valid data into its `data_buffer`. Only then does it proceed to the write state, now holding the correct data.

This debugging session highlights a fundamental principle of bus-master design: **a master must account for the latency of the slaves it communicates with.** The `S_READ_WAIT` state explicitly handles the one-cycle read latency of our on-chip RAM.