// riscv_top.v -- top-level single-cycle RV32I CPU.
//
// This module does not compute anything itself. Its only job is
// "wiring": instantiate every functional block (PC, instruction memory,
// register file, immediate generator, the two decoders, the ALU, the
// branch comparator, data memory, and the UART peripheral) and connect
// them exactly the way the RV32I single-cycle datapath requires, plus a
// handful of small muxes that don't deserve their own module (choosing the
// ALU's A input, choosing the register write-back value, choosing the next
// PC). Every one of those muxes is controlled by a signal main_decoder.v
// produced by looking at nothing but the opcode.
//
// Read this module top-to-bottom and you're reading the datapath itself:
// Fetch (PC, instr_mem) -> Decode (fields, main_decoder, alu_decoder,
// reg_file read, imm_gen) -> Execute (ALU, branch_comp) -> Memory
// (data_mem, uart_mmio) -> Write-back (result mux into reg_file).
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

    // ------------------------------------------------------------------
    // Fetch
    // ------------------------------------------------------------------
    wire [31:0] pc;
    wire [31:0] pc_next;
    wire [31:0] pc_plus4;
    wire [31:0] instr;

    program_counter u_pc (
        .clk     (clk),
        .rst_n   (rst_n),
        .pc_next (pc_next),
        .pc      (pc)
    );

    assign pc_plus4 = pc + 32'd4;

    instr_mem #(
        .MEM_FILE  (IMEM_FILE),
        .MEM_WORDS (IMEM_WORDS)
    ) u_instr_mem (
        .addr  (pc),
        .instr (instr)
    );

    // ------------------------------------------------------------------
    // Decode -- pull the fixed instruction fields straight out of `instr`
    // ------------------------------------------------------------------
    wire [6:0] opcode   = instr[6:0];
    wire [4:0] rd_addr  = instr[11:7];
    wire [2:0] funct3   = instr[14:12];
    wire [4:0] rs1_addr = instr[19:15];
    wire [4:0] rs2_addr = instr[24:20];
    wire       funct7b5 = instr[30];

    wire        reg_write;
    wire [2:0]  imm_src;
    wire        alu_src;
    wire        mem_write_ctrl;
    wire [1:0]  result_src;
    wire        branch;
    wire        jump;
    wire        jalr;
    wire [1:0]  alu_op;
    wire [1:0]  alu_a_src;

    main_decoder u_main_decoder (
        .opcode     (opcode),
        .reg_write  (reg_write),
        .imm_src    (imm_src),
        .alu_src    (alu_src),
        .mem_write  (mem_write_ctrl),
        .result_src (result_src),
        .branch     (branch),
        .jump       (jump),
        .jalr       (jalr),
        .alu_op     (alu_op),
        .alu_a_src  (alu_a_src)
    );

    wire [3:0] alu_control;
    alu_decoder u_alu_decoder (
        .alu_op      (alu_op),
        .funct3      (funct3),
        .funct7b5    (funct7b5),
        .op5         (instr[5]),
        .alu_control (alu_control)
    );

    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] result;   // write-back value -- driven from the write-back mux below

    reg_file u_reg_file (
        .clk (clk),
        .we3 (reg_write),
        .a1  (rs1_addr),
        .a2  (rs2_addr),
        .a3  (rd_addr),
        .wd3 (result),
        .rd1 (rs1_data),
        .rd2 (rs2_data)
    );

    wire [31:0] imm_ext;
    imm_gen u_imm_gen (
        .instr   (instr),
        .imm_src (imm_src),
        .imm_ext (imm_ext)
    );

    // ------------------------------------------------------------------
    // Execute
    // ------------------------------------------------------------------

    // ALU A input: rs1 for almost everything, pc for AUIPC, 0 for LUI.
    reg [31:0] alu_src_a;
    always @(*) begin
        case (alu_a_src)
            2'b00:   alu_src_a = rs1_data;
            2'b01:   alu_src_a = pc;
            2'b10:   alu_src_a = 32'd0;
            default: alu_src_a = rs1_data;
        endcase
    end

    wire [31:0] alu_src_b = alu_src ? imm_ext : rs2_data;

    wire [31:0] alu_result;
    wire        alu_zero;   // unused directly (branch_comp handles all branch conditions), kept for visibility in waveforms

    alu u_alu (
        .a           (alu_src_a),
        .b           (alu_src_b),
        .alu_control (alu_control),
        .result      (alu_result),
        .zero        (alu_zero)
    );

    wire branch_taken;
    branch_comp u_branch_comp (
        .rs1_data (rs1_data),
        .rs2_data (rs2_data),
        .funct3   (funct3),
        .taken    (branch_taken)
    );

    // Separate adder for branch/JAL targets, exactly like a real RV32I
    // datapath: it runs every cycle in parallel with the ALU so the target
    // is ready immediately if the branch turns out to be taken, without
    // costing an extra cycle to compute it only after the fact.
    wire [31:0] pc_target = pc + imm_ext;

    // ------------------------------------------------------------------
    // Memory
    // ------------------------------------------------------------------
    wire [31:0] dmem_read_data;
    wire        uart_sel;
    wire [31:0] uart_read_data;

    data_mem #(
        .MEM_BYTES (DMEM_BYTES),
        .MEM_FILE  (DMEM_FILE)
    ) u_data_mem (
        .clk        (clk),
        .addr       (alu_result),
        .write_data (rs2_data),
        .mem_write  (mem_write_ctrl && !uart_sel),
        .funct3     (funct3),
        .read_data  (dmem_read_data)
    );

    uart_mmio #(
        .CLKS_PER_BIT (UART_CLKS_PER_BIT),
        .BASE_ADDR    (UART_BASE_ADDR)
    ) u_uart_mmio (
        .clk        (clk),
        .rst_n      (rst_n),
        .addr       (alu_result),
        .write_data (rs2_data),
        .mem_write  (mem_write_ctrl),
        .read_data  (uart_read_data),
        .sel        (uart_sel),
        .tx         (uart_tx_line)
    );

    wire [31:0] mem_read_data = uart_sel ? uart_read_data : dmem_read_data;

    // ------------------------------------------------------------------
    // Write-back
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

    // ------------------------------------------------------------------
    // Next-PC mux
    // ------------------------------------------------------------------
    wire pc_src = jump || (branch && branch_taken);

    reg [31:0] pc_next_mux;
    always @(*) begin
        if (jalr)
            pc_next_mux = (alu_result & 32'hFFFF_FFFE); // clear bit 0, per the RV32I spec
        else if (pc_src)
            pc_next_mux = pc_target;                    // taken branch or JAL
        else
            pc_next_mux = pc_plus4;                      // sequential execution
    end
    assign pc_next = pc_next_mux;

endmodule
