// tb_riscv_top.v -- comprehensive, self-checking testbench for the
// single-cycle RV32I CPU (book Tasks 11-12).
//
// This follows the self-checking pattern Task 8 formalized for the rest of
// this book: a `task automatic` does the checking, `$readmemh` loads the
// expected values from a file instead of hard-coding them into Verilog,
// and every mismatch is reported with `$display` before the final
// pass/fail summary -- "accumulate and report," the same style Task 4's
// exhaustive ALU testbench and Task 7's UART sweep both use, because this
// test is many independent checks (one per instruction/instruction group)
// rather than a single sequential scenario where an early failure makes
// every later check meaningless.
//
// What's actually being verified: asm/cpu_test.s is a single RV32I
// program that exercises every base instruction this CPU implements except
// `sb` (exercised on hardware as hello_hw.s's UART store), and logs one
// 32-bit "checkpoint" result per instruction (or small group) into
// sequential data-memory words, starting at address 0. asm/gen_expected.py
// independently recomputes, in Python, what each checkpoint SHOULD be --
// the same "independent reference model" idea as Task 4's `expected_result`
// task, in a different language so it can't share a bug with either the
// assembly program or the CPU RTL. This testbench's only job is to run
// the program to completion and compare the two.
`timescale 1ns/1ps

module tb_riscv_top;

    localparam NUM_CHECKPOINTS = 41;
    localparam RUN_CYCLES      = 400;  // generous upper bound -- see asm/cpu_test.s;
                                        // 165 static instructions, no backward loops
                                        // except the final self-loop, so this is far
                                        // more cycles than the program can possibly need.

    reg clk;
    reg rst_n;
    wire uart_tx_line;   // unused by this testbench -- exercised for real in
                          // scripts/project4_riscv_verify's hardware build instead

    // Instantiate the DUT with the test program in instruction memory and
    // no preloaded data memory (cpu_test.s doesn't need any -- everything
    // it stores, it stores itself).
    riscv_top #(
        .IMEM_FILE  ("cpu_test.hex"),
        .IMEM_WORDS (256),
        .DMEM_BYTES (1024),
        .DMEM_FILE  ("")
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .uart_tx_line (uart_tx_line)
    );

    // Free-running clock, 10ns period (100MHz) -- the CPU's actual speed
    // doesn't matter for a functional check like this one; only clock
    // EDGES matter, not their real-world timing.
    always #5 clk = ~clk;

    // --- Expected checkpoint values, loaded from the Python-generated file ---
    reg [31:0] expected [0:NUM_CHECKPOINTS-1];
    initial $readmemh("expected.hex", expected);

    integer errors;

    // The instruction behind each checkpoint (see asm/cpu_test.s, [chk N]),
    // so a result names the instruction to fix, not just a number.
    reg [8*20-1:0] names [0:NUM_CHECKPOINTS-1];
    initial begin
        names[ 0] = "addi x5, x0, 5      ";
        names[ 1] = "addi x6, x0, -3     ";
        names[ 2] = "andi x7, x5, 3      ";
        names[ 3] = "ori  x8, x5, 2      ";
        names[ 4] = "xori x9, x5, 3      ";
        names[ 5] = "slti x10, x6, 0     ";
        names[ 6] = "sltiu x11, x6, 5    ";
        names[ 7] = "slli x12, x5, 2     ";
        names[ 8] = "srli x13, x6, 4     ";
        names[ 9] = "srai x14, x6, 4     ";
        names[10] = "add  x15, x5, x6    ";
        names[11] = "sub  x16, x5, x6    ";
        names[12] = "and  x17, x5, x8    ";
        names[13] = "or   x18, x5, x9    ";
        names[14] = "xor  x19, x5, x9    ";
        names[15] = "sll  x20, x5, x7    ";
        names[16] = "srl  x21, x6, x7    ";
        names[17] = "sra  x22, x6, x7    ";
        names[18] = "slt  x23, x6, x5    ";
        names[19] = "sltu x24, x6, x5    ";
        names[20] = "lui  x25, 0x12345   ";
        names[21] = "auipc x26, 1        ";
        names[22] = "lw   x29, 0(x27)    ";
        names[23] = "lb   x29, 0(x27)    ";
        names[24] = "lbu  x29, 0(x27)    ";
        names[25] = "sh + lh  x31, 8(x27)";
        names[26] = "sh + lhu x31, 8(x27)";
        names[27] = "beq (taken)         ";
        names[28] = "beq (not taken)     ";
        names[29] = "bne (taken)         ";
        names[30] = "bne (not taken)     ";
        names[31] = "blt (taken)         ";
        names[32] = "blt (not taken)     ";
        names[33] = "bge (taken)         ";
        names[34] = "bge (not taken)     ";
        names[35] = "bltu (taken)        ";
        names[36] = "bltu (not taken)    ";
        names[37] = "bgeu (taken)        ";
        names[38] = "bgeu (not taken)    ";
        names[39] = "jal  (call lands)   ";
        names[40] = "jalr (return)       ";
    end

    // Reads one 32-bit checkpoint word directly out of the DUT's data
    // memory array. This is the testbench reaching in with a hierarchical
    // reference (`dut.u_memory.u_data_mem.mem`) rather than going through
    // the CPU's own load instructions -- deliberately, so that a bug in LW
    // itself can't accidentally "hide" a bug in what SW actually wrote.
    function automatic [31:0] read_checkpoint(input integer index);
        reg [31:0] byte_addr;
        begin
            byte_addr = index * 4;
            read_checkpoint = { dut.u_memory.u_data_mem.mem[byte_addr+3],
                                 dut.u_memory.u_data_mem.mem[byte_addr+2],
                                 dut.u_memory.u_data_mem.mem[byte_addr+1],
                                 dut.u_memory.u_data_mem.mem[byte_addr]   };
        end
    endfunction

    task automatic check_checkpoint(input integer index);
        reg [31:0] got, exp;
        begin
            got = read_checkpoint(index);
            exp = expected[index];
            if (got !== exp) begin
                errors = errors + 1;
                $display("[FAIL] checkpoint %2d  %s  got 0x%08h, expected 0x%08h", index, names[index], got, exp);
            end else
                $display("[PASS] checkpoint %2d  %s  0x%08h", index, names[index], got);
        end
    endtask

    integer k;
    initial begin
        clk   = 1'b0;
        rst_n = 1'b0;
        errors = 0;

        // Poison the checkpoint region with 0xA5 (never a correct result)
        // before the CPU runs. data_mem starts all-zero, so without this a
        // checkpoint whose EXPECTED value is 0 (the sltiu/sltu ones) would
        // "pass" even if its `sw` never executed. With it, every checkpoint
        // is genuine proof that the CPU wrote it. The `#1` waits until every
        // time-0 `initial` block (including data_mem's zero-fill) has run --
        // Verilog doesn't define their order -- so the poison always lands
        // last. Reset is still held until 20 ns, so the CPU hasn't run yet.
        #1;
        for (k = 0; k < NUM_CHECKPOINTS * 4; k = k + 1)
            dut.u_memory.u_data_mem.mem[k] = 8'hA5;

        // Hold reset for a couple of cycles, then release it -- the CPU
        // starts fetching from address 0 the instant rst_n goes high.
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // Let the program run to completion (and settle into its final
        // self-loop) before inspecting anything.
        repeat (RUN_CYCLES) @(negedge clk);

        for (k = 0; k < NUM_CHECKPOINTS; k = k + 1)
            check_checkpoint(k);

        if (errors == 0)
            $display("RV32I CPU testbench PASSED all %0d checkpoints.", NUM_CHECKPOINTS);
        else
            $display("RV32I CPU testbench FAILED %0d / %0d checkpoints.", errors, NUM_CHECKPOINTS);

        $finish;
    end

endmodule
