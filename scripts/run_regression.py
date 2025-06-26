# Copyright (c) 2025 Kumar Vedang
# SPDX-License-Identifier: MIT
#
# This source file is part of the RISC-V SoC project.
#

import os
import subprocess

# --- Configuration ---
TEST_CASES = [
    "DMA_TEST",
    "CRC_TEST",
    "TIMER_TEST",
    "UART_LOOPBACK_TEST",
    "CORNER_CASE_TEST",
    "FULL_REGRESSION" # Runs all tests sequentially
]

# --- Configuration ---
# List of Verilog/SystemVerilog files to be compiled.
# The paths are relative to the project's root directory.
# The order is critical to satisfy module dependencies.
COMPILE_ORDER = [
    # RTL Files
    "rtl/on_chip_ram.v",
    "rtl/crc32_accelerator.v",
    "rtl/timer.v",
    "rtl/uart_tx.v",
    "rtl/uart_rx.v",
    "rtl/uart_top.v",
    "rtl/address_decoder.v",
    "rtl/arbiter.v",
    "rtl/interrupt_controller.v",
    "rtl/dma_engine.v",
    "rtl/simple_cpu.v",
    "rtl/risc_soc.sv",
    # Testbench File
    "tb/tb_risc_soc.sv"
]

COMPILE_FILES_STR = " ".join(COMPILE_ORDER)
IV_COMPILE_CMD = f"iverilog -g2005-sv -o soc_sim {COMPILE_FILES_STR}"

def main():
    # (The rest of the script logic is unchanged)
    print("=======================================")
    print("=== Starting RISC-V SoC Regression ===")
    print("=======================================")
    print(f"\n--- Compiling the design using explicit order ---")
    print(f"Compile Command: {IV_COMPILE_CMD}")
    try:
        subprocess.run(IV_COMPILE_CMD, shell=True, check=True, capture_output=True, text=True)
        print("Compilation successful.")
    except subprocess.CalledProcessError as e:
        print("[ERROR] Compilation failed!")
        print(e.stderr)
        return

    results = {}
    for test in TEST_CASES:
        print(f"\n--- Running Test: {test} ---")
        run_cmd = f"vvp soc_sim +TESTNAME={test}"
        try:
            sim_output = subprocess.check_output(run_cmd, shell=True, text=True)
            with open(f"log_{test}.txt", "w") as f: f.write(sim_output)
            if "All Transactions PASSED" in sim_output or "Test Successful" in sim_output:
                print(f"[STATUS] PASSED")
                results[test] = "PASS"
            elif "TEST FAILED" in sim_output or "ERROR" in sim_output:
                print(f"[STATUS] FAILED")
                results[test] = "FAIL"
            else:
                print(f"[STATUS] UNKNOWN - Could not determine pass/fail.")
                results[test] = "UNKNOWN"
        except subprocess.CalledProcessError as e:
            print(f"[ERROR] Simulation crashed for test: {test}")
            results[test] = "CRASH"
    
    print("\n=======================================")
    print("=== Regression Summary ===")
    print("=======================================")
    all_passed = True
    for test, result in results.items():
        print(f"  {test:<20} : {result}")
        if result != "PASS": all_passed = False
    print("---------------------------------------")
    if all_passed:
        print(">>> ALL TESTS PASSED! Regression successful. <<<")
    else:
        print(">>> REGRESSION FAILED! Check logs for details. <<<")
    print("=======================================")

if __name__ == "__main__":
    main()


