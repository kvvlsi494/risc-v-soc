# Architectural Deep Dive

## 1. High-Level Philosophy

The SoC is designed as a **memory-mapped, multi-master system** built around a simple, synchronous shared bus. The architecture was deliberately chosen to explore the core challenges of system integration:
- **Resource Contention:** How to manage access when multiple masters (CPU, DMA) want to use the bus simultaneously.
- **System Integration:** How to connect disparate IP blocks (with different functions) into a cohesive whole.
- **Hardware/Software Interface:** How a processor controls and communicates with its peripherals via memory-mapped registers and interrupts.

## 2. System Block Diagram

The diagram below illustrates the flow of control and data signals between the masters, the central interconnect logic, and the slave peripherals.

```mermaid
graph TD
    subgraph " "
        direction LR
        subgraph "MASTERS"
            CPU(simple_cpu<br/>Master 0)
            DMA_M(dma_engine<br/>Master 1)
        end

        subgraph "INTERCONNECT"
            Arbiter(Arbiter)
            BusMux(Bus Multiplexers)
            AddressDecoder(Address Decoder)
            RdataMux(RDATA MUX)
        end
    end

    subgraph "SLAVES"
        direction LR
        RAM(on_chip_ram)
        DMA_S(dma_engine<br/>Slave Port)
        CRC(crc32_accelerator)
        Timer(timer)
        UART(uart_top)
        INTC(interrupt_controller)
    end
    
    subgraph "CPU & INTERRUPTS"
        direction LR
        CPU_IRQ_Port(CPU<br/>irq_in)
    end

    %% Master to Interconnect Connections
    CPU -- "m_req_0" --> Arbiter
    Arbiter -- "m_gnt_0" --> CPU
    DMA_M -- "m_req_1" --> Arbiter
    Arbiter -- "m_gnt_1" --> DMA_M

    CPU -- "master bus 0" --> BusMux
    DMA_M -- "master bus 1" --> BusMux
    BusMux -- " bus_addr, bus_wdata, bus_wr_en  " --> AddressDecoder

    %% Address Decoder to Slaves
    AddressDecoder -- "ram_cs_n" --> RAM
    AddressDecoder -- "dma_cs_n" --> DMA_S
    AddressDecoder -- "crc_cs_n" --> CRC
    AddressDecoder -- "timer_cs_n" --> Timer
    AddressDecoder -- "uart_cs_n" --> UART
    AddressDecoder -- "intc_cs_n" --> INTC
    
    %% Bus to Slaves
    AddressDecoder -- "bus signals" --> RAM
    AddressDecoder -- "bus signals" --> DMA_S
    AddressDecoder -- "bus signals" --> CRC
    AddressDecoder -- "bus signals" --> Timer
    AddressDecoder -- "bus signals" --> UART
    AddressDecoder -- "bus signals" --> INTC

    %% Read Data Path from Slaves
    RAM -- "rdata" --> RdataMux
    DMA_S -- "rdata" --> RdataMux
    CRC -- "rdata" --> RdataMux
    Timer -- "rdata" --> RdataMux
    UART -- "rdata" --> RdataMux
    INTC -- "rdata" --> RdataMux
    RdataMux -- "bus_rdata" --> BusMux
    
    %% Read Data Path to Masters
    BusMux -- "bus_rdata" --> CPU
    BusMux -- "bus_rdata" --> DMA_M

    %% Interrupt Path
    DMA_M -- "dma_done" --> INTC
    Timer -- "irq_out" --> INTC
    UART -- "irq_out" --> INTC
    INTC -- "irq_out" --> CPU_IRQ_Port

    %% Styling
    style CPU fill:#cce5ff,stroke:#333,stroke-width:2px
    style DMA_M fill:#cce5ff,stroke:#333,stroke-width:2px
    style Arbiter fill:#e6ccff,stroke:#333,stroke-width:2px
    style BusMux fill:#e6ccff,stroke:#333,stroke-width:2px
    style AddressDecoder fill:#e6ccff,stroke:#333,stroke-width:2px
    style RdataMux fill:#e6ccff,stroke:#333,stroke-width:2px
    style RAM fill:#d4edda,stroke:#333,stroke-width:2px
    style DMA_S fill:#d4edda,stroke:#333,stroke-width:2px
    style CRC fill:#d4edda,stroke:#333,stroke-width:2px
    style Timer fill:#d4edda,stroke:#333,stroke-width:2px
    style UART fill:#d4edda,stroke:#333,stroke-width:2px
    style INTC fill:#d4edda,stroke:#333,stroke-width:2px
    style CPU_IRQ_Port fill:#f8d7da,stroke:#333,stroke-width:2px
```

## 3. Component Deep Dive

### The Masters
*   **`simple_cpu`**: The primary master, responsible for executing control code. It initiates bus transactions to fetch instructions and configure peripherals.
*   **`dma_engine`**: The secondary master. After being configured by the CPU via its slave port, it independently requests the bus to perform high-speed memory-to-memory transfers.

### The Interconnect
*   **`arbiter`**: A fixed-priority arbiter that resolves bus requests. It receives `m_req_0` (from CPU) and `m_req_1` (from DMA) and asserts a single grant (`m_gnt_0` or `m_gnt_1`), giving priority to the CPU.
*   **`Bus Multiplexers`**: A set of MUXs in `risc_soc.sv` that use the arbiter's grant signal as a select line to route the winning master's address, data, and control signals onto the shared system bus.
*   **`address_decoder`**: A purely combinational block that translates the upper bits of the system address bus into a single active-low chip select (`_cs_n`) signal for the target slave.

## 4. System Memory Map
The address space is partitioned as follows:

| Address Range           | Module                 |
|-------------------------|------------------------|
| `0x0000_0000-0x0000_FFFF` | `on_chip_ram`          |
| `0x0001_0000-0x0001_FFFF` | `dma_engine` (slave)   |
| `0x0002_0000-0x0002_FFFF` | `crc32_accelerator`    |
| `0x0003_0000-0x0003_FFFF` | `interrupt_controller` |
| `0x0004_0000-0x0004_FFFF` | `timer`                |
| `0x0005_0000-0x0005_FFFF` | `uart_top`             |
