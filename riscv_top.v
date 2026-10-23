// riscv_top.v -- top-level single-cycle RV32I CPU.
//
// Wires four stage modules together -- Fetch, Decode, Execute, Memory --
// plus the write-back mux, which is small enough it doesn't need a module
// of its own. See the course book's Task 11 for the full datapath
// walkthrough and Task 12 for the memory-mapped UART peripheral.
module riscv_top #(
    parameter IMEM_FILE       = "hello_uart.hex",
    parameter IMEM_WORDS      = 256,
    parameter DMEM_BYTES      = 1024,
    parameter DMEM_FILE       = "hello_data.hex",
    parameter UART_CLKS_PER_BIT = 434,               // 50_000_000 / 115200 baud
    parameter [31:0] UART_BASE_ADDR = 32'h0000_0400  // just past the end of data RAM
)(
    input  clk,
    input  rst_n,
    output uart_tx_line
);

    // Fetch <-> Decode/Execute
    wire [31:0] pc, instr, pc_plus4;

    // Decode -> Execute/Memory
    wire [2:0]  funct3;
    wire        alu_src;
    wire [1:0]  alu_a_src;
    wire        mem_write_ctrl;
    wire [1:0]  result_src;
    wire        branch, jump, jalr;
    wire [3:0]  alu_control;
    wire [31:0] rs1_data, rs2_data, imm_ext;

    // Execute -> Fetch/Memory
    wire [31:0] alu_result, pc_target;
    wire        branch_taken;

    // Memory -> write-back
    wire [31:0] mem_read_data;

    // Write-back -> Decode's register file
    wire [31:0] result;

    fetch_stage #(
        .IMEM_FILE  (IMEM_FILE),
        .IMEM_WORDS (IMEM_WORDS)
    ) u_fetch (
        .clk          (clk),
        .rst_n        (rst_n),
        .jump         (jump),
        .jalr         (jalr),
        .branch       (branch),
        .branch_taken (branch_taken),
        .alu_result   (alu_result),
        .pc_target    (pc_target),
        .pc           (pc),
        .instr        (instr),
        .pc_plus4     (pc_plus4)
    );

    decode_stage u_decode (
        .clk         (clk),
        .instr       (instr),
        .wd3         (result),
        .funct3      (funct3),
        .alu_src     (alu_src),
        .alu_a_src   (alu_a_src),
        .mem_write   (mem_write_ctrl),
        .result_src  (result_src),
        .branch      (branch),
        .jump        (jump),
        .jalr        (jalr),
        .alu_control (alu_control),
        .rs1_data    (rs1_data),
        .rs2_data    (rs2_data),
        .imm_ext     (imm_ext)
    );

    execute_stage u_execute (
        .pc           (pc),
        .rs1_data     (rs1_data),
        .rs2_data     (rs2_data),
        .imm_ext      (imm_ext),
        .alu_src      (alu_src),
        .alu_a_src    (alu_a_src),
        .alu_control  (alu_control),
        .funct3       (funct3),
        .alu_result   (alu_result),
        .branch_taken (branch_taken),
        .pc_target    (pc_target)
    );

    memory_stage #(
        .DMEM_BYTES        (DMEM_BYTES),
        .DMEM_FILE         (DMEM_FILE),
        .UART_CLKS_PER_BIT (UART_CLKS_PER_BIT),
        .UART_BASE_ADDR    (UART_BASE_ADDR)
    ) u_memory (
        .clk          (clk),
        .rst_n        (rst_n),
        .addr         (alu_result),
        .write_data   (rs2_data),
        .mem_write    (mem_write_ctrl),
        .funct3       (funct3),
        .read_data    (mem_read_data),
        .uart_tx_line (uart_tx_line)
    );

    // ------------------------------------------------------------------
    // Write-back -- the one piece of the datapath with no dedicated
    // module: pick what gets written back to rd.
    // ------------------------------------------------------------------
    reg [31:0] result_mux;
    always @(*) begin
        case (result_src)
            2'b00:   result_mux = alu_result;      // R-type/I-type ALU ops, LUI, AUIPC
            2'b01:   result_mux = mem_read_data;    // loads
            2'b10:   result_mux = pc_plus4;         // JAL/JALR return address
            default: result_mux = alu_result;
        endcase
    end
    assign result = result_mux;

endmodule
