# References and Specifications

This project was developed by referencing the official specifications for the RISC-V ISA and standard digital design principles.

## Core Specifications

1.  **RISC-V Instruction Set Manual:** The design of the `simple_cpu` core, including the opcodes and instruction formats for LW, SW, ADDI, and BEQ, directly follows the standards laid out in the official RISC-V ISA manual.
    - [The RISC-V Instruction Set Manual, Volume I: Unprivileged ISA](https://riscv.org/technical/specifications/)

2.  **CRC-32 (Ethernet Polynomial):** The CRC algorithm implemented in the `crc32_accelerator` uses the standard polynomial (`0x04C11DB7`) as defined for Ethernet (IEEE 802.3) and many other networking standards.
    - [Painless Guide to CRC Error Detection Algorithms](http://www.sunshine2k.de/articles/coding/crc/understanding_crc.html) - An excellent practical guide on CRC implementation.

## Recommended Reading

- **"Digital Design and Computer Architecture, RISC-V Edition" by Harris & Harris:** A foundational textbook that covers many of the principles used in this project, from digital logic and FSMs to CPU pipelining and memory systems.