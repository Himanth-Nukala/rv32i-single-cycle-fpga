// uart_mmio.v -- wraps uart_tx.v as a tiny memory-mapped peripheral.
//
// This is exactly the "memory-mapped I/O" idea Project 3 built with an
// external UART command bus, now seen from the other side: instead of a
// host PC issuing bus writes, the CPU's own `sw` instruction is the one
// writing to a special address. From software's point of view, "print a
// character" is just "store a byte to this one fixed address" -- no special
// instruction, no interrupt, nothing the CPU's datapath needs to know about.
//
// Two word-aligned addresses are recognized, relative to BASE_ADDR:
//   BASE_ADDR + 0  (TX_DATA)   write-only.  sw here starts transmitting
//                              write_data[7:0] over the serial line.
//   BASE_ADDR + 4  (TX_STATUS) read-only.   bit 0 = 1 while a byte is still
//                              being shifted out ("busy"). A program must
//                              poll this and wait for it to read 0 before
//                              writing the next character, or bytes would
//                              get dropped.
module uart_mmio #(
    parameter CLKS_PER_BIT = 434,          // 50_000_000 / 115200 baud
    parameter [31:0] BASE_ADDR = 32'h0000_0400
)(
    input             clk,
    input             rst_n,

    // CPU-facing bus
    input      [31:0] addr,
    input      [31:0] write_data,
    input             mem_write,
    output     [31:0] read_data,
    output            sel,        // 1 when `addr` belongs to this peripheral

    // Serial-port-facing pin
    output            tx
);

    localparam [31:0] TX_DATA_ADDR   = BASE_ADDR;
    localparam [31:0] TX_STATUS_ADDR = BASE_ADDR + 32'd4;

    wire is_data_write = mem_write && (addr == TX_DATA_ADDR);
    wire tx_busy;

    assign sel       = (addr == TX_DATA_ADDR) || (addr == TX_STATUS_ADDR);
    assign read_data = { 31'd0, tx_busy };   // only TX_STATUS is readable; harmless if TX_DATA is read too

    uart_tx #(
        .CLKS_PER_BIT (CLKS_PER_BIT)
    ) u_uart_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (is_data_write),
        .tx_data  (write_data[7:0]),
        .tx       (tx),
        .tx_busy  (tx_busy)
    );

endmodule
