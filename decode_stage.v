// decode_stage.v -- the Decode stage: instruction-field extraction, the
// two-level control decode (main_decoder + alu_decoder), the register
// file, and immediate generation. See the course book's Task 11 for why
// decode is split into two decoders and how imm_gen reassembles RV32I's
// scrambled immediate encoding.
module decode_stage (
    input             clk,
    input      [31:0] instr,
    input      [31:0] wd3,          // write-back value, from riscv_top's write-back mux

    output     [2:0]  funct3,
    output            alu_src,
    output     [1:0]  alu_a_src,
    output            mem_write,
    output     [1:0]  result_src,
    output            branch,
    output            jump,
    output            jalr,
    output     [3:0]  alu_control,
    output     [31:0] rs1_data,
    output     [31:0] rs2_data,
    output     [31:0] imm_ext
);

    wire [6:0] opcode   = instr[6:0];
    wire [4:0] rd_addr  = instr[11:7];
    wire [4:0] rs1_addr = instr[19:15];
    wire [4:0] rs2_addr = instr[24:20];
    wire       funct7b5 = instr[30];

    assign funct3 = instr[14:12];

    wire       reg_write;
    wire [2:0] imm_src;
    wire [1:0] alu_op;

    main_decoder u_main_decoder (
        .opcode     (opcode),
        .reg_write  (reg_write),
        .imm_src    (imm_src),
        .alu_src    (alu_src),
        .mem_write  (mem_write),
        .result_src (result_src),
        .branch     (branch),
        .jump       (jump),
        .jalr       (jalr),
        .alu_op     (alu_op),
        .alu_a_src  (alu_a_src)
    );

    alu_decoder u_alu_decoder (
        .alu_op      (alu_op),
        .funct3      (funct3),
        .funct7b5    (funct7b5),
        .op5         (instr[5]),
        .alu_control (alu_control)
    );

    reg_file u_reg_file (
        .clk (clk),
        .we3 (reg_write),
        .a1  (rs1_addr),
        .a2  (rs2_addr),
        .a3  (rd_addr),
        .wd3 (wd3),
        .rd1 (rs1_data),
        .rd2 (rs2_data)
    );

    imm_gen u_imm_gen (
        .instr   (instr),
        .imm_src (imm_src),
        .imm_ext (imm_ext)
    );

endmodule
