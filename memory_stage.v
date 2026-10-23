// memory_stage.v -- the Memory stage: data RAM and the memory-mapped
// UART peripheral, sharing one address space. See the course book's
// Task 12 for the address map and why the UART read-data mux takes
// priority over ordinary RAM.
module memory_stage #(
    parameter DMEM_BYTES        = 1024,
    parameter DMEM_FILE         = "hello_data.hex",
    parameter UART_CLKS_PER_BIT = 434,
    parameter [31:0] UART_BASE_ADDR = 32'h0000_0400
)(
    input             clk,
    input             rst_n,
    input      [31:0] addr,
    input      [31:0] write_data,
    input             mem_write,
    input      [2:0]  funct3,

    output     [31:0] read_data,
    output            uart_tx_line
);

    wire [31:0] dmem_read_data;
    wire        uart_sel;
    wire [31:0] uart_read_data;

    data_mem #(
        .MEM_BYTES (DMEM_BYTES),
        .MEM_FILE  (DMEM_FILE)
    ) u_data_mem (
        .clk        (clk),
        .addr       (addr),
        .write_data (write_data),
        .mem_write  (mem_write && !uart_sel),
        .funct3     (funct3),
        .read_data  (dmem_read_data)
    );

    uart_mmio #(
        .CLKS_PER_BIT (UART_CLKS_PER_BIT),
        .BASE_ADDR    (UART_BASE_ADDR)
    ) u_uart_mmio (
        .clk        (clk),
        .rst_n      (rst_n),
        .addr       (addr),
        .write_data (write_data),
        .mem_write  (mem_write),
        .read_data  (uart_read_data),
        .sel        (uart_sel),
        .tx         (uart_tx_line)
    );

    assign read_data = uart_sel ? uart_read_data : dmem_read_data;

endmodule
