// tb_riscv_top.v -- comprehensive, self-checking testbench for the
// single-cycle RV32I CPU.
//
// This follows the exact same pattern Task 11 formalized for the rest of
// this book: a `task automatic` does the checking, `$readmemh` loads the
// expected values from a file instead of hard-coding them into Verilog,
// and every mismatch is reported with `$display` before the final
// pass/fail summary -- "accumulate and report," the same style Task 6's
// exhaustive ALU testbench and Task 9's UART sweep both use, because this
// test is many independent checks (one per instruction/instruction group)
// rather than a single sequential scenario where an early failure makes
// every later check meaningless.
//
// What's actually being verified: asm/cpu_test.s is a single RV32I
// program that exercises every base instruction this CPU implements, and
// logs one 32-bit "checkpoint" result per instruction (or small group of
// instructions) into sequential data-memory words, starting at address 0.
// asm/gen_expected.py is a completely independent re-implementation, in
// Python, of what each of those checkpoints SHOULD be -- exactly the same
// "independent reference model" idea as Task 6's `expected_result` task,
// just written in a different language so it can't share a bug with
// either the assembly program or the CPU RTL. This testbench's only job is
// to run the program to completion and compare the two.
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

    // Reads one 32-bit checkpoint word directly out of the DUT's data
    // memory array. This is the testbench reaching in with a hierarchical
    // reference (`dut.u_data_mem.mem`) rather than going through the CPU's
    // own load instructions -- deliberately, so that a bug in LW itself
    // can't accidentally "hide" a bug in what SW actually wrote.
    function automatic [31:0] read_checkpoint(input integer index);
        reg [31:0] byte_addr;
        begin
            byte_addr = index * 4;
            read_checkpoint = { dut.u_data_mem.mem[byte_addr+3],
                                 dut.u_data_mem.mem[byte_addr+2],
                                 dut.u_data_mem.mem[byte_addr+1],
                                 dut.u_data_mem.mem[byte_addr]   };
        end
    endfunction

    task automatic check_checkpoint(input integer index);
        reg [31:0] got, exp;
        begin
            got = read_checkpoint(index);
            exp = expected[index];
            if (got !== exp) begin
                errors = errors + 1;
                $display("[FAIL] checkpoint %0d: got 0x%08h, expected 0x%08h", index, got, exp);
            end
        end
    endtask

    integer k;
    initial begin
        clk   = 1'b0;
        rst_n = 1'b0;
        errors = 0;

        // Poison the checkpoint region of data memory with a value that
        // can never look like a correct result (0xA5) before the CPU runs.
        // Without this, a checkpoint whose EXPECTED value happens to be 0
        // (like the sltiu/sltu checkpoints below) would silently "pass"
        // even if the `sw` that was supposed to write it never executed --
        // data memory already resets to all-zero, so a missing write and a
        // correct-but-zero write would be indistinguishable. Poisoning
        // first means every checkpoint is a genuine proof that the CPU
        // wrote it, not just that memory happened to start out agreeing.
        for (k = 0; k < NUM_CHECKPOINTS * 4; k = k + 1)
            dut.u_data_mem.mem[k] = 8'hA5;

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
