// tb_hello_uart.v -- end-to-end check of the exact program and data file
// that get flashed onto the DE0-Nano: run the CPU with hello.s in
// instruction memory and the greeting string in data memory, capture every
// byte it actually transmits over `uart_tx_line` with a real `uart_rx`
// instance (the same module Task 7 verified), and compare the received
// string against what we expect character-by-character.
//
// This is the closest thing to "testing it on hardware" that's possible
// before the design ever touches Quartus: if the CPU, the UART peripheral,
// and the assembled program all agree here, in simulation, at the RTL
// level, the only things left for hardware to prove are pin mapping and
// the real board's clock/reset -- not the processor's actual behavior.
`timescale 1ns/1ps

module tb_hello_uart;

    localparam CLKS_PER_BIT = 434;              // matches riscv_top's default (50MHz / 115200 baud)
    localparam EXPECTED_LEN = 16;                // "Hello, RISC-V!\r\n" -- not counting the null terminator

    // The expected characters, loaded straight from the very same file
    // that seeds the CPU's data memory -- hello_data.hex is 17 bytes (the
    // 16-character string plus its null terminator); we only compare the
    // first 16, since hello.s stops transmitting the instant it reads that
    // terminating zero.
    reg [7:0] expected_str [0:16];
    initial $readmemh("hello_data.hex", expected_str);

    reg clk;
    reg rst_n;
    wire tx_line;

    riscv_top #(
        .IMEM_FILE  ("hello_uart.hex"),
        .IMEM_WORDS (256),
        .DMEM_BYTES (1024),
        .DMEM_FILE  ("hello_data.hex")
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .uart_tx_line (tx_line)
    );

    // A real 50MHz clock would make this simulation take forever (17
    // characters * 10 bits/char * 434 cycles/bit at a real 50MHz period).
    // Since only *edges* matter for a functional check, not real-world
    // timing, we run the same CLKS_PER_BIT relationship at a much faster
    // simulated clock instead -- this is purely a simulation-speed trick;
    // riscv_top itself is never told the clock is "fast."
    always #5 clk = ~clk;   // 10ns period

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

    integer char_index;
    integer errors;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        char_index = 0;
        errors = 0;

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
    end

    // Every time uart_rx finishes a byte, check it against the next
    // expected character -- an accumulate-and-report check, same pattern
    // as tb_riscv_top.v, since a wrong character early on shouldn't stop
    // us from seeing whether the rest of the string still comes through.
    always @(posedge clk) begin
        if (rx_valid) begin
            if (char_index < EXPECTED_LEN) begin
                if (rx_data !== expected_str[char_index]) begin
                    errors = errors + 1;
                    $display("[FAIL] char %0d: got '%c' (0x%02h), expected '%c' (0x%02h)",
                              char_index, rx_data, rx_data, expected_str[char_index], expected_str[char_index]);
                end else begin
                    $display("[ OK ] char %0d: '%c' (0x%02h)", char_index, rx_data, rx_data);
                end
            end else begin
                errors = errors + 1;
                $display("[FAIL] received extra byte 0x%02h after the expected string ended", rx_data);
            end
            char_index = char_index + 1;
        end
    end

    // Give the CPU comfortably more time than 16 characters at 115200
    // baud actually need, then grade the run.
    initial begin
        #2_000_000;   // 2ms of simulated time
        if (char_index < EXPECTED_LEN) begin
            errors = errors + 1;
            $display("[FAIL] only received %0d / %0d characters before timing out", char_index, EXPECTED_LEN);
        end

        if (errors == 0)
            $display("hello.s UART testbench PASSED -- received the greeting correctly.");
        else
            $display("hello.s UART testbench FAILED with %0d error(s).", errors);

        $finish;
    end

endmodule
