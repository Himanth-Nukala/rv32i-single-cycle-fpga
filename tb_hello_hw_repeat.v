// tb_hello_hw_repeat.v -- confirms hello_hw.s's outer loop actually works:
// that after sending the string once and running the delay loop, control
// correctly jumps back to `main` and sends the string a second time. Runs
// against hello_hw_sim.hex, which is asm/hello_hw.s assembled with a much
// shorter delay count (20 iterations instead of 3,000,000) purely so this
// simulates in a couple of milliseconds instead of tens of seconds -- the
// delay loop itself (addi/bne counting down to zero) is the same
// already-verified logic tb_riscv_top.v's branch checkpoints cover, so
// this testbench's only real job is proving the jump back to `main` lands
// correctly and the string sends again cleanly, back-to-back.
`timescale 1ns/1ps

module tb_hello_hw_repeat;

    localparam CLKS_PER_BIT = 434;
    localparam STRING_LEN   = 16;
    localparam NUM_REPEATS  = 3;

    reg [7:0] expected_str [0:16];
    initial $readmemh("hello_data.hex", expected_str);

    reg clk;
    reg rst_n;
    wire tx_line;

    riscv_top #(
        .IMEM_FILE  ("hello_hw_sim.hex"),
        .IMEM_WORDS (256),
        .DMEM_BYTES (1024),
        .DMEM_FILE  ("hello_data.hex")
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .uart_tx_line (tx_line)
    );

    always #5 clk = ~clk;

    wire [7:0] rx_data;
    wire       rx_valid;
    uart_rx #(
        .CLKS_PER_BIT (CLKS_PER_BIT)
    ) u_uart_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .rx       (tx_line),
        .rx_data  (rx_data),
        .rx_valid (rx_valid)
    );

    integer total_index;
    integer errors;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        total_index = 0;
        errors = 0;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (rx_valid) begin
            if (rx_data !== expected_str[total_index % STRING_LEN]) begin
                errors = errors + 1;
                $display("[FAIL] byte %0d (repeat %0d, char %0d): got 0x%02h, expected 0x%02h",
                          total_index, total_index / STRING_LEN, total_index % STRING_LEN,
                          rx_data, expected_str[total_index % STRING_LEN]);
            end
            total_index = total_index + 1;
        end
    end

    initial begin
        #3_000_000;   // comfortably more than NUM_REPEATS full messages + delays need
        if (total_index < NUM_REPEATS * STRING_LEN) begin
            errors = errors + 1;
            $display("[FAIL] only received %0d / %0d expected bytes across %0d repeats",
                      total_index, NUM_REPEATS * STRING_LEN, NUM_REPEATS);
        end

        if (errors == 0)
            $display("hello_hw.s repeat-loop testbench PASSED -- %0d repeats received correctly.",
                      total_index / STRING_LEN);
        else
            $display("hello_hw.s repeat-loop testbench FAILED with %0d error(s).", errors);

        $finish;
    end

endmodule
