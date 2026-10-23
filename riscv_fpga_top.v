// riscv_fpga_top.v -- the FPGA-facing top level.
//
// riscv_top.v itself is already board-agnostic (just clk/rst_n/uart_tx_line),
// so this wrapper's only job is the usual one for this book: connect the
// DE0-Nano's actual pins (its 50MHz oscillator, KEY[0] as an active-low
// reset, and the two GPIO pins wired to the CH340G USB-serial adapter) to
// the CPU, and put something visible on the LEDs so students get immediate
// feedback that the design is alive on real silicon, not just in
// simulation.
module riscv_fpga_top (
    input        CLOCK_50,
    input  [1:0] KEY,
    output [7:0] LED,
    output       GPIO_0_TX,   // -> PIN_C3 -> CH340G RXD (this is the FPGA's UART transmit pin)
    input        GPIO_0_RX    // -> PIN_D3 <- CH340G TXD (reserved: this CPU doesn't implement UART receive yet)
);

    wire rst_n = KEY[0];

    // GPIO_0_RX is intentionally unused -- see the module comment above.
    // Naming it here (instead of leaving the pin unconstrained) keeps the
    // physical wiring description in the book's Task 12 accurate even though nothing
    // in this design reads it yet.
    wire unused_rx = GPIO_0_RX;

    // hello_hw.s is only 15 instructions and its string is 17 bytes, so
    // instruction/data memory are sized just for that program (with a
    // little headroom), not the 256-word/1024-byte sizes tb_riscv_top.v
    // uses to exercise every instruction in simulation. This matters for
    // real hardware in a way it never does in simulation: data_mem's
    // byte-array, written at up to 4 independent addresses in the same
    // cycle for `sw`, isn't a pattern Quartus can map onto a block RAM --
    // it has to unroll the whole array into raw logic cells. At 1024
    // bytes that unrolled the array into single-handedly ~30,000+ logic
    // elements (see Task 12, "Fitting a CPU on Real Hardware") -- more than the EP4CE22 has in
    // total. At the size this program actually needs, the same RTL costs
    // only a few thousand.
    riscv_top #(
        .IMEM_FILE  ("hello_hw.hex"),
        .IMEM_WORDS (64),    // 256 bytes -- comfortably covers 15 instructions
        .DMEM_BYTES (64),    // comfortably covers the 17-byte greeting string
        .DMEM_FILE  ("hello_data.hex")
    ) u_cpu (
        .clk          (CLOCK_50),
        .rst_n        (rst_n),
        .uart_tx_line (GPIO_0_TX)
    );

    // A visible heartbeat: LED[0] is bit 24 of a 50 MHz counter, so it
    // changes every 2^24 / 50e6 = 0.34 s and completes one on-off blink
    // every 0.67 s (about 1.5 blinks per second). That makes it obvious at a glance that the CPU's clock is actually running, even
    // before anyone has opened a serial terminal to see the UART output.
    reg [24:0] heartbeat_counter;
    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n)
            heartbeat_counter <= 25'd0;
        else
            heartbeat_counter <= heartbeat_counter + 25'd1;
    end

    assign LED[0]   = heartbeat_counter[24];
    assign LED[7:1] = 7'b0;

endmodule
