# Copyright (c) 2025 Kumar Vedang
# SPDX-License-Identifier: MIT
#
# This source file is part of the RISC-V SoC project.
#

"""
--------------------------------------------------------------------------------
-- File Name: run_regression.py
-- Project: A Simple RISC-V SoC with DMA-Driven Peripherals
-- Author: Kumar Vedang
--------------------------------------------------------------------------------
--
-- High-Level Script Purpose:
-- This Python script is the master controller for the entire verification
-- process. It serves as the "Regression Manager," providing a single,
-- push-button entry point to compile the entire SoC design and run a full
-- suite of verification tests. Its primary role is to automate a process that
-- would otherwise be tedious, manual, and error-prone.
--
-- Significance in the Project Workflow:
-- In any professional VLSI project, running tests manually is not feasible. As
-- the design evolves, it's critical to be able to quickly and reliably re-run
-- all existing tests to ensure that new changes have not broken old functionality.
-- This is known as "regression testing." This script is the engine that drives
-- our regression methodology. It provides:
--
--   1. Consistency: It ensures that the design is always compiled with the
--      exact same commands and file order, eliminating a common source of errors.
--   2. Efficiency: It transforms a multi-step, multi-command process into a
--      single command (`python3 run_regression.py`), saving a significant amount
--      of time and effort.
--   3. Automation: It automatically runs each test, parses the resulting log
--      files for pass/fail keywords, and generates a clean, easy-to-read
--      summary report. This allows an engineer to quickly assess the health
--      of the design at a glance.
--
-- This script is the glue that connects the RTL design, the SystemVerilog
-- testbench, and the command-line tools (Icarus Verilog) into a cohesive,
-- professional, and automated verification flow.
--
--------------------------------------------------------------------------------
"""

# --- Library Imports ---
# This section imports the necessary built-in Python libraries. A library is a
# collection of pre-written code and functions that provides functionalities
# that are not part of the core Python language. Importing them allows our
# script to perform more advanced operations, particularly for interacting
# with the operating system and other programs.

# The `os` library provides a portable way of using operating system dependent
# functionality. While not heavily used in this specific version of the script,
# it is almost always imported in utility scripts like this for tasks such as
# checking if files exist (`os.path.exists`), creating directories (`os.makedirs`),
# or constructing file paths in an OS-agnostic way (`os.path.join`). Its
# presence here indicates good practice and foresight for future script
# enhancements.
import os



# The `subprocess` library is the most critical import for this script.
# Its purpose is to allow a Python script to spawn new processes, connect to
# their input/output/error pipes, and obtain their return codes.
#
# Why is this essential? This library is the bridge between our Python
# automation script and the command-line EDA tools (`iverilog` and `vvp`).
# We will use functions from this library, specifically `subprocess.run()` and
# `subprocess.check_output()`, to execute the compilation and simulation
# commands as if we were typing them directly into a terminal. This allows our
# script to control the entire VLSI toolchain, capture the results, and make
#-- decisions based on the outcome.
import subprocess



# --- Test Case and Compilation Configuration ---
# This section defines the core configuration of the regression script. By
# placing all user-configurable items in one place at the top of the file, the
# script becomes much easier to maintain and extend. An engineer can add a new
# test case or a new source file by editing only these lists, without having to
# search for and modify the core execution logic. This is a fundamental
# principle of good software design.

# `TEST_CASES`: This is a Python list of strings that defines the complete
# suite of tests to be run.
#
# What it represents: Each string in this list must correspond exactly to a
# `TESTNAME` that the SystemVerilog testbench (`tb_risc_soc.sv`) can understand
# via the `$value$plusargs` system task. This list is the "master plan" for
# the regression.
#
# How it's used: The main execution loop of this script will iterate through
# this list, running one simulation for each entry. For example, for the entry
# "DMA_TEST", the script will execute the command `vvp soc_sim +TESTNAME=DMA_TEST`.
#
# Why this is important: This makes adding a new test trivial. To add a new
# "I2C_TEST", I would first implement the `run_i2c_test` task in the testbench,
# add the logic to the test sequencer, and then simply add the string
# "I2C_TEST" to this list. No other changes to this script would be needed.
TEST_CASES = [
    "DMA_TEST",
    "CRC_TEST",
    "TIMER_TEST",
    "UART_LOOPBACK_TEST",
    "CORNER_CASE_TEST",
    "FULL_REGRESSION" # This is a special case that runs all other tests.
]

# --- Configuration ---
# List of Verilog/SystemVerilog files to be compiled.
# The paths are relative to the project's root directory.
# The order is critical to satisfy module dependencies.

# `COMPILE_ORDER`: This is a Python list of strings that specifies every
# single Verilog and SystemVerilog source file required to compile the design
# and its testbench.
#
# Why order is critical: Verilog compilers, especially simpler ones like
# Icarus Verilog, are often single-pass compilers. This means that if a module
# (`module B`) instantiates another module (`module A`), the file containing
# `module A` must be listed *before* the file containing `module B` in the
# compilation command. This list is carefully ordered to respect these
# dependencies, with the lowest-level RTL files first and the top-level
# testbench file last.
#
# How it's used: The script will join all the strings in this list together
# with spaces in between to form the file list portion of the final `iverilog`
# compile command. Centralizing this list prevents compilation failures due
# to incorrect file ordering and makes it easy to add new RTL files to the project.
COMPILE_ORDER = [
     # RTL Files - From simplest peripherals to most complex
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
    
    # Top-level SoC integrator
    "rtl/risc_soc.sv",
    
    # Top-level Testbench
    "tb/tb_risc_soc.sv"
]


# --- Compile Command Generation ---
# This section programmatically constructs the complete compilation command string.
# By building the command from the configuration variables above, we ensure that
# any changes to the file list are automatically reflected in the command,
# making the script robust and maintainable.

# This line uses the `join()` string method in Python.
#   - `" ".join(...)`: This is a powerful and efficient way to concatenate all
#     the elements of a list into a single string.
#   - The `" "` part specifies the separator to be placed *between* each element.
#   - `COMPILE_ORDER`: This is the list of file paths we are joining.
#
# The result is that the `COMPILE_FILES_STR` variable will hold a single string
# like: "rtl/on_chip_ram.v rtl/crc32_accelerator.v ... tb/tb_risc_soc.sv"
# This perfectly formatted string is now ready to be inserted into the full
# command.
COMPILE_FILES_STR = " ".join(COMPILE_ORDER)


# This line uses a Python f-string (formatted string literal) to construct the
# final, complete shell command for compilation. F-strings provide a concise
# and readable way to embed expressions and variables directly into a string.
#
# The f-string is broken down as follows:
#   - `iverilog`: The name of the command-line tool to execute.
#   - `-g2005-sv`: The essential flag to enable SystemVerilog features in the
#     compiler.
#   - `-o soc_sim`: The flag to specify the name of the output executable file,
#     `soc_sim`.
#   - `{COMPILE_FILES_STR}`: This is the placeholder where the f-string will
#     substitute the entire content of the `COMPILE_FILES_STR` variable we created
#     in the previous line.
#
# The resulting `IV_COMPILE_CMD` variable now holds the complete, ready-to-execute
# command that will be passed to the shell.
IV_COMPILE_CMD = f"iverilog -g2005-sv -o soc_sim {COMPILE_FILES_STR}"



# The `main` function encapsulates the primary logic of the script. This is a
# standard Python convention that improves code organization and allows the
# script to be potentially importable by other Python modules without
# immediately executing its code.
def main():
    
    # Print a banner to the console to indicate the start of the process. This
    # kind of user feedback is crucial for long-running scripts.
    print("=======================================")
    print("=== Starting RISC-V SoC Regression ===")
    print("=======================================")
    
    
    # --- Step 1: Compilation ---
    # This phase attempts to compile the entire design and testbench. If this
    # step fails, there is no point in attempting to run any simulations, so the
    # script should exit.
    print(f"\n--- Compiling the design using explicit order ---")
    
    # This line prints the exact command that will be executed, which is
    # invaluable for debugging the script itself.
    print(f"Compile Command: {IV_COMPILE_CMD}")
    
    
    # This `try...except` block is a robust error-handling mechanism. The script
    # will "try" to execute the code within the `try` block. If that code
    # raises a specific type of error (an "exception"), the script will not
    # crash; instead, it will jump to the `except` block to handle the error
    # gracefully.
    try:
        
        
        # `subprocess.run()` is the function that executes the external command.
        # It takes several important arguments:
        #   - `IV_COMPILE_CMD`: The string variable holding the full compile command.
        #   - `shell=True`: This tells the function to execute the command through
        #     the system's default shell (like Bash on Linux). This is necessary
        #     for the shell to interpret the command string correctly.
        #   - `check=True`: This is a critical argument. If the command returns
        #     a non-zero exit code (which indicates an error, e.g., a compile
        #     error), this will automatically raise a `CalledProcessError`
        #     exception, triggering the `except` block.
        #   - `capture_output=True`, `text=True`: These arguments capture the
        #     standard output and standard error streams from the command and
        #     decode them as text.

        subprocess.run(IV_COMPILE_CMD, shell=True, check=True, capture_output=True, text=True)
        
        # If `subprocess.run` completes without raising an exception, it means
        # the compilation was successful (returned an exit code of 0).
        print("Compilation successful.")
        
    # This `except` clause will only execute if the `subprocess.run` command
    # failed (because `check=True` was set).
    except subprocess.CalledProcessError as e:
        
        # The `e` object contains information about the error.
        # Print a clear error message to the user.
        print("[ERROR] Compilation failed!")
        
        # `e.stderr` contains the standard error output from the failed command,
        # which will include the specific Verilog error messages from `iverilog`.
        # Printing this is essential for debugging the RTL or testbench code.
        print(e.stderr)
        
        # The script terminates here, as there is no point continuing if the
        # design did not compile.
        return
    
    
    # --- Step 2: Simulation Loop ---
    # This section executes after a successful compilation. It iterates through
    # each test case, runs the simulation, and records the result.

    # `results`: This initializes an empty Python dictionary.
    #
    # What is a dictionary? It is a data structure that stores key-value pairs.
    #
    # How is it used here? This dictionary will be used to store the outcome of
    # the entire regression run. The "key" will be the name of the test (e.g.,
    # "DMA_TEST"), and the "value" will be its result status (e.g., "PASS" or
    # "FAIL"). This provides a structured way to collect all the results before
    # printing the final summary.
    results = {}
    
    # This `for` loop is the main engine of the regression. It iterates through
    # every element in the `TEST_CASES` list that was defined at the top of the
    # script. For each iteration, the current test name from the list is assigned
    # to the variable `test`.
    for test in TEST_CASES:
        
        # This print statement provides real-time feedback to the user, showing
        # which specific test is about to be executed. This is crucial for
        # monitoring the progress of a long regression run.
        print(f"\n--- Running Test: {test} ---")
        
        
        # This f-string constructs the specific command needed to run one test.
        #   - `vvp`: This is the Icarus Verilog runtime engine that executes the
        #     compiled simulation file.
        #   - `soc_sim`: This is the name of the executable file created by the
        #     `iverilog` command in the compilation step.
        #   - `+TESTNAME={test}`: This is the critical "plusarg". The `{test}`
        #     placeholder is replaced with the current test name from the loop
        #     (e.g., "DMA_TEST"). This entire string is passed to the simulator,
        #     allowing the SystemVerilog testbench to read it and select the
        #     correct test task to execute.
        run_cmd = f"vvp soc_sim +TESTNAME={test}"
        
        # This `try...except` block handles the execution of a single simulation.
        # This is essential because one test might crash or fail, but we want
        # the regression script to continue running the other tests.
        try:
            
            
            # `subprocess.check_output()` is used here instead of `run()`. It is
            # similar, but it directly returns the standard output of the command
            # as a Python variable. It will also raise a `CalledProcessError` if
            # the command returns a non-zero exit code (i.e., if the simulation
            # terminates with a `$error` or `$finish(2)` in the Verilog code).
            #   - `shell=True`: Again, needed to interpret the command string correctly.
            #   - `text=True`: Ensures the returned output is a normal Python string.
            
            sim_output = subprocess.check_output(run_cmd, shell=True, text=True)
            
            
            # --- Log File Archiving ---
            # This line performs a critical function for any serious regression
            # system: it archives the complete output of the simulation to a
            # dedicated log file.
            #
            # How it works:
            #   - `with open(...) as f:`: This is the standard, robust way to
            #     handle files in Python. It automatically manages opening and
            #     closing the file, even if errors occur.
            #   - `f"log_{test}.txt"`: This f-string dynamically creates a unique
            #     filename for each test. For example, when running the "DMA_TEST",
            #     it will create a file named "log_DMA_TEST.txt".
            #   - `"w"`: This opens the file in "write" mode, which will create a
            #     new file or overwrite an existing one.
            #   - `f.write(sim_output)`: This writes the entire captured output
            #     from the simulation (all the `$display` messages) into the file.
            #
            # Why is this so important?
            # When a test fails, the brief "FAIL" message on the console is not
            # enough to debug the problem. The engineer needs to see the full
            # context: which specific transaction failed, what were the addresses,
            # what was the mismatched data? This log file contains all of that
            # detailed information printed by the testbench. It is the first
            # and most essential piece of evidence used to begin the debugging
            # process. Without these archived logs, debugging a regression
            # failure would be nearly impossible.
            with open(f"log_{test}.txt", "w") as f: f.write(sim_output)
            
            # --- Result Parsing Logic (Log File Grep) ---
            # This block of code acts as an intelligent "grep" or search function.
            # Its purpose is to parse the `sim_output` string (which contains the
            # entire simulation log) to find specific keywords that indicate the
            # outcome of the test. This is the core of automated pass/fail detection.

            # The `if` condition checks for the presence of known "pass" signatures.
            #   - `in` is a Python operator that returns `True` if a substring is
            #     found within a larger string.
            #   - `"Test Successful"` is the final message printed by the testbench
            #     upon successful completion of any test.
            #   - `"All Transactions PASSED"` is a backup check, demonstrating how
            #     multiple pass conditions can be handled.
            # If either of these strings is found, the test is considered a success.
            if "All Transactions PASSED" in sim_output or "Test Successful" in sim_output:
                
                # Print a clear status message to the console for the user.
                print(f"[STATUS] PASSED")
                
                # Update the results dictionary, storing "PASS" as the value
                # for the current test's key.
                results[test] = "PASS"
                
            # The `elif` (else if) condition checks for known "fail" signatures.
            # This is only checked if the "pass" condition was false.
            #   - `"TEST FAILED"` or `"ERROR"` are the keywords printed by the
            #     testbench's `$error` system task calls.
            # The presence of either of these keywords definitively indicates a failure.
            elif "TEST FAILED" in sim_output or "ERROR" in sim_output:
                print(f"[STATUS] FAILED")
                
                # Store "FAIL" in the results dictionary.
                results[test] = "FAIL"
                
            # The `else` block is a catch-all. It executes if neither a clear
            # pass nor a clear fail signature was found in the log file.
            else:
                
                # This could happen if the testbench hangs, or if there's a bug
                # in the testbench's display messages.
                print(f"[STATUS] UNKNOWN - Could not determine pass/fail.")
                
                # It's important to flag this as "UNKNOWN" rather than assuming
                # a pass, as it indicates a problem with the verification
                # environment itself that needs investigation.
                results[test] = "UNKNOWN"
                
        # This `except` block catches a simulation that has crashed (returned
        # a non-zero exit code).
        except subprocess.CalledProcessError as e:
            
            # Print a clear message indicating which test failed to complete.
            print(f"[ERROR] Simulation crashed for test: {test}")
            
            # Record the result as a "CRASH" in our results dictionary.
            results[test] = "CRASH"
    
    
    # This final block of code executes after all tests in the suite have been
    # run. Its sole purpose is to process the `results` dictionary and present a
    # clean, formatted, and conclusive summary to the user. This is the ultimate
    # output of the regression script.

    # Print a clear header for the summary section in the console output.
    print("\n=======================================")
    print("=== Regression Summary ===")
    print("=======================================")
    
     # `all_passed`: This initializes a boolean "flag" variable to True.
    # What is its purpose? It will be used to keep track of the overall success
    # of the entire regression. We start with the optimistic assumption that
    # everything has passed. This flag will be "pulled down" to False if we
    # encounter even a single non-passing test.
    all_passed = True
    
    # This `for` loop iterates through all the key-value pairs stored in the
    # `results` dictionary.
    #   - `.items()`: This is a dictionary method that returns an iterable view
    #     of the dictionary's pairs.
    #   - `for test, result in ...`: On each iteration, the key is assigned to
    #     the `test` variable, and its corresponding value is assigned to the
    #     `result` variable.
    for test, result in results.items():
        
        # This uses an f-string to print a single, formatted line for each test.
        #   - `{test:<20}`: This is a formatting specifier. The `<` character
        #     left-aligns the string, and the `20` reserves a total of 20
        #     character spaces for the test name. This ensures that the results
        #     are printed in a neat, aligned column, regardless of the length
        #     of the test names.
        #   - `: {result}`: Prints the pass/fail status for that test.
        print(f"  {test:<20} : {result}")
        
        # This `if` statement checks the status of the current test.
        # If the result for this test is anything other than "PASS" (e.g.,
        # "FAIL", "CRASH", "UNKNOWN"), the overall regression is considered a failure.
        if result != "PASS":
            
            # The `all_passed` flag is set to False. Once this flag is set to
            # False, it will remain False for the rest of the loop, correctly
            # capturing that at least one test has failed.
            all_passed = False
    print("---------------------------------------")
    
    # This final `if/else` statement checks the overall status flag `all_passed`
    # to print the final, conclusive verdict of the entire regression run.
    if all_passed:
        
        # This message is printed only if every single test in the suite returned
        # a "PASS" status.
        print(">>> ALL TESTS PASSED! Regression successful. <<<")
    else:
        
        # If the `all_passed` flag was pulled down to False at any point, this
        # message is printed, immediately alerting the user that there is a
        # problem that requires investigation. The user is prompted to check the
        # generated log files for the specific failure details.
        print(">>> REGRESSION FAILED! Check logs for details. <<<")
    print("=======================================")




# This is a standard Python construct. The `__name__` variable is a special
# built-in variable which evaluates to the name of the current module. However,
# if the script is being executed directly from the command line (and not
# imported by another script), `__name__` is set to the string `"__main__"`.
# Therefore, this `if` statement ensures that the `main()` function is called
# only when this script is the top-level program being run.
if __name__ == "__main__":
    main()





"""
--------------------------------------------------------------------------------
--                              PROJECT ANALYSIS
--------------------------------------------------------------------------------
--
--
-- ############################################################################
-- ##                     Methodology and Implementation                     ##
-- ############################################################################
--
--
-- [[ Relevance of This File ]]
--
-- This Python script, `run_regression.py`, is the conductor of the entire
-- verification orchestra. While the SystemVerilog testbench (`tb_risc_soc.sv`)
-- defines the individual tests, this script provides the critical top-level
-- automation that makes the verification process efficient, repeatable, and
-- scalable. Its relevance cannot be overstated; it elevates the project from a
-- collection of manually-run simulations to a professional, automated regression
-- suite. It represents the "push-button" that a design or verification engineer
-- would press to get a definitive, high-level answer to the question: "Is the
-- state of the design good?"
--
--
-- [[ Key Concepts Implemented ]]
--
-- This script is a practical demonstration of several key concepts from the
-- domain of software engineering and DevOps as applied to VLSI verification:
--
--   1. Automation: The core concept is the automation of the entire compile-run-
--      check cycle. This script codifies a manual, multi-step process into a
--      single, reliable command.
--
--   2. Command-Line Orchestration: It demonstrates how a high-level scripting
--      language (Python) can be used to control and orchestrate a set of low-level,
--      specialized command-line tools (`iverilog`, `vvp`). This is a fundamental
--      pattern in system administration and industrial automation.
--
--   3. Configuration Management: By defining the file lists and test cases as
--      centralized Python lists, the script implements a simple form of
--      configuration management. This makes the entire regression suite easy to
--      modify and extend without changing the core logic.
--
--   4. Robust Error Handling: The use of `try...except` blocks to catch both
--      compilation failures and simulation crashes makes the script robust. It
--      can distinguish between a test that fails functionally and one that fails
--      to even run, providing more precise feedback for debugging.
--
--
-- [[ My Implementation Flow ]]
--
-- I developed this script iteratively as the project's complexity grew.
--
--   - Initial Stage (Manual Commands): Initially, when I only had one or two
--     tests, I ran the `iverilog` and `vvp` commands manually in the terminal.
--     This was feasible but quickly became repetitive.
--
--   - Creating the Script Outline: I realized I needed automation. I started by
--     creating a new Python file. My first goal was to simply replicate the
--     manual compile and run commands for a single test using `subprocess.run()`.
--
--   - Generalizing with Lists: Once I could run one test, I generalized the
--     script. I created the `TEST_CASES` and `COMPILE_ORDER` lists so that the
--     commands were built programmatically from these configurations, rather than
--     being hard-coded strings.
--
--   - Adding the Loop and Results Dictionary: I then wrapped the simulation-
--     running logic in a `for` loop to iterate through the `TEST_CASES` list. I
--     also introduced the `results` dictionary at this stage to store the outcome
--     of each test.
--
--   - Implementing Result Parsing: The most crucial logic was added next: the
--     `if/elif/else` chain to parse the `sim_output` for pass/fail keywords. I
--     made sure my SystemVerilog testbench printed a consistent, unique string
--     ("--- Test Successful. ---") to make this parsing reliable.
--
--   - Final Touches (Error Handling & Summary): Finally, I wrapped the execution
--     calls in `try...except` blocks to make the script more robust and added the
--     final summary-printing loop to provide a clean, high-level report at the
--     end of the regression run.
--
--------------------------------------------------------------------------------
"""




"""
--
-- ############################################################################
-- ##                    Industrial Context and Insights                     ##
-- ############################################################################
--
--
-- [[ Industrial Applications ]]
--
-- This Python script is a small-scale, but conceptually identical, version of
-- the automated regression systems that are the backbone of every modern
-- semiconductor company. While this script runs locally, in industry, this
-- same logic would be part of a much larger, distributed system.
--
--   1. Nightly and Continuous Integration (CI) Regressions: At companies like
--      NVIDIA, Intel, or AMD, design teams check in new code daily. Every night,
--      a powerful automated system, often managed by tools like Jenkins or
--      Buildbot, checks out the latest version of the design and uses a script
--      like this one to launch thousands of simulations on a massive server
--      farm. This script's ability to run different tests, parse logs, and
--      generate a summary is exactly what those industrial systems do. The
--      morning report from this regression tells the entire team the health of
--      the project.
--
--   2. Gate-Level Simulation (GLS) Automation: After a design is synthesized,
--      it must be re-verified with "gate-level" simulations, which are much
--      slower. Automation is even more critical here. A script like this would
--      be adapted to run a smaller, targeted set of tests on the synthesized
--      netlist to verify timing and check for tool-induced errors.
--
--   3. Cross-Functional Tool Flow: In a real project, this script could be
--      extended to do more than just run simulations. It could be the "glue"
--      that runs synthesis with Synopsys Design Compiler, then runs the
--      simulation with VCS, then runs a formal verification check with JasperGold,
--      all in a single, automated sequence. A DV or CAD (Computer-Aided Design)
--      engineer's job often involves writing and maintaining these complex
--      cross-functional tool-flow scripts.
--
--
-- [[ Industrially Relevant Insights Gained ]]
--
-- Writing and using this script provided critical insights into the professional
-- engineering mindset, particularly regarding the value of automation.
--
--   - Technical Insight: The Testbench API is a Contract. I learned that for
--     automation to work, there must be a strict "contract" between the testbench
--     and the automation script. The plusarg `+TESTNAME=` is part of that contract.
--     The pass/fail signatures ("Test Successful", "ERROR") are another part. If a
--     verification engineer changes these strings in the testbench without
--     updating the script, the entire automated system breaks. This highlights the
--     need for clear documentation and communication between the person writing
--     the tests and the person writing the automation.
--
--   - Non-Technical Insight: The Return on Investment (ROI) of Automation.
--     Initially, writing this script took time that could have been spent running
--     tests manually. However, the ROI became apparent very quickly. A manual
--     regression of all 5 tests might take 5-10 minutes of focused effort
--     (typing commands, checking logs). This script does it in about 15 seconds
--     with zero effort. Over the lifetime of the project, this script saved
--     dozens of hours. This taught me a key business lesson: investing time
--     upfront to automate a repetitive process is one of the highest-leverage
--     activities an engineer can perform. It directly improves productivity,
--     reduces human error, and allows engineers to focus on more valuable tasks
--     like designing new tests or debugging complex failures.
--
--------------------------------------------------------------------------------
"""



"""
--
--
-- ############################################################################
-- ##                    Environment and Final Execution                     ##
-- ############################################################################
--
--
-- [[ Development Environment ]]
--
-- This script was developed and tested within a standard, open-source software
-- environment, demonstrating proficiency with tools commonly used for both
-- software development and VLSI scripting.
--
--   - Operating System: The primary development was done on a Linux-based OS
--     (like Ubuntu), which is the standard in the semiconductor industry. The use
--     of OS-agnostic libraries like `os` and `subprocess` ensures the script would
--     also be portable to other systems like macOS or Windows (with appropriate
--     toolchains installed).
--   - Text Editor: Visual Studio Code (VS Code) was used for its powerful Python
--     support, including linting (with Pylint/Flake8), debugging, and an
--     integrated terminal for seamless execution.
--   - Python Version: The script is written in Python 3 (specifically 3.6+ to
--     support f-strings), which is the current standard for the language.
--   - Toolchain: This script directly orchestrates the Icarus Verilog toolchain
--     (`iverilog`, `vvp`) and relies on GTKWave for manual waveform debug when
--     failures are investigated.
--
--
-- [[ Final Execution Command ]]
--
-- The entire verification suite for this SoC project, encompassing compilation
-- of over a dozen RTL files and the execution of all five major test categories,
-- is launched from the root directory of the project with a single, simple command:
--
--   `python3 run_regression.py`
--
-- Upon execution, this command will:
--   1. Invoke `iverilog` to compile the entire SoC design and testbench.
--   2. If compilation succeeds, it will sequentially invoke `vvp` for each test
--      case defined in the `TEST_CASES` list.
--   3. For each test, it will create a corresponding log file (e.g., `log_DMA_TEST.txt`).
--   4. It will parse the output from each test to determine its pass/fail status.
--   5. Finally, it will print a formatted summary report to the console, giving
--      the final verdict on the regression's success.
--
-- This single command represents the culmination of the entire verification effort,
-- providing the ultimate "push-button" solution for quality assurance.
--
--------------------------------------------------------------------------------
"""