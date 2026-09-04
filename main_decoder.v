// main_decoder.v -- the primary control unit.
//
// Looks ONLY at the 7-bit opcode (instr[6:0]) and produces every control
// signal the rest of the datapath needs, except the exact ALU operation
// (that's alu_decoder.v's job -- see the comment there for why they're
// split).
//
// This module is pure combinational logic: it is a truth table, opcode in,
// control bits out. There is deliberately no clock here.
module main_decoder (
    input      [6:0] opcode,
    output reg       reg_write,   // 1 = instruction writes a result back to rd
    output reg [2:0] imm_src,     // which immediate format to build (see imm_gen.v)
    output reg       alu_src,     // 0 = ALU's B input is rs2, 1 = it's the immediate
    output reg       mem_write,   // 1 = store instruction (write data memory)
    output reg [1:0] result_src,  // what gets written back to rd (see below)
    output reg       branch,      // 1 = this is a conditional branch instruction
    output reg       jump,        // 1 = this is JAL or JALR (unconditional jump)
    output reg       jalr,        // 1 = specifically JALR (target comes from the ALU, not the PC adder)
    output reg [1:0] alu_op,      // coarse hint for alu_decoder.v
    output reg [1:0] alu_a_src    // what feeds the ALU's A input (see below)
);

    // alu_a_src: almost every instruction feeds rs1 into the ALU's A input.
    // Two instructions are the exception, and both build their result purely
    // from the immediate and one other value:
    //   00 -> rs1                     (R-type, I-type ALU ops, loads, stores, branches, JALR)
    //   01 -> pc                      (AUIPC: result = pc + immediate)
    //   10 -> zero                    (LUI: result = 0 + immediate = immediate)

    // result_src: what value the register file's write port actually receives
    //   00 -> the ALU result             (R-type, I-type ALU ops, LUI's add-with-0 trick)
    //   01 -> data memory read data      (loads)
    //   10 -> pc + 4                     (JAL/JALR return address)
    //   11 -> the ALU result, but the ALU's A input was forced to 0 (AUIPC uses pc, so
    //         AUIPC actually reuses result_src=00 with alu_src fed pc -- see riscv_top.v)

    // imm_src: which instruction format's immediate to decode (see imm_gen.v)
    //   000 = I-type   001 = S-type   010 = B-type   011 = J-type   100 = U-type

    // RV32I base opcodes used in this project
    localparam OP_RTYPE  = 7'b0110011; // ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
    localparam OP_ITYPE  = 7'b0010011; // ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI
    localparam OP_LOAD   = 7'b0000011; // LB, LH, LW, LBU, LHU
    localparam OP_STORE  = 7'b0100011; // SB, SH, SW
    localparam OP_BRANCH = 7'b1100011; // BEQ, BNE, BLT, BGE, BLTU, BGEU
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;

    always @(*) begin
        // Safe defaults: an unrecognized opcode does nothing (no writes,
        // no branch/jump), rather than corrupting state.
        reg_write  = 1'b0;
        imm_src    = 3'b000;
        alu_src    = 1'b0;
        mem_write  = 1'b0;
        result_src = 2'b00;
        branch     = 1'b0;
        jump       = 1'b0;
        jalr       = 1'b0;
        alu_op     = 2'b00;
        alu_a_src  = 2'b00;

        case (opcode)
            OP_RTYPE: begin
                reg_write  = 1'b1;
                alu_src    = 1'b0;   // ALU B input = rs2
                result_src = 2'b00;  // write ALU result
                alu_op     = 2'b10;  // let alu_decoder look at funct3/funct7
            end

            OP_ITYPE: begin
                reg_write  = 1'b1;
                imm_src    = 3'b000; // I-type immediate
                alu_src    = 1'b1;   // ALU B input = immediate
                result_src = 2'b00;
                alu_op     = 2'b10;
            end

            OP_LOAD: begin
                reg_write  = 1'b1;
                imm_src    = 3'b000; // I-type immediate (address offset)
                alu_src    = 1'b1;
                result_src = 2'b01;  // write memory read data
                alu_op     = 2'b00;  // ALU just adds base + offset
            end

            OP_STORE: begin
                imm_src    = 3'b001; // S-type immediate (address offset)
                alu_src    = 1'b1;
                mem_write  = 1'b1;
                alu_op     = 2'b00;  // ALU just adds base + offset
            end

            OP_BRANCH: begin
                imm_src    = 3'b010; // B-type immediate (branch offset)
                alu_src    = 1'b0;   // ALU compares rs1 vs rs2
                branch     = 1'b1;
                alu_op     = 2'b01;  // ALU subtracts, or check the specific branch condition
            end

            OP_JAL: begin
                reg_write  = 1'b1;
                imm_src    = 3'b011; // J-type immediate (jump offset)
                jump       = 1'b1;
                result_src = 2'b10;  // write pc+4 (the return address)
            end

            OP_JALR: begin
                reg_write  = 1'b1;
                imm_src    = 3'b000; // I-type immediate (jump offset)
                alu_src    = 1'b1;
                jump       = 1'b1;
                jalr       = 1'b1;
                result_src = 2'b10;  // write pc+4 (the return address)
                alu_op     = 2'b00;  // ALU computes rs1 + immediate
            end

            OP_LUI: begin
                reg_write  = 1'b1;
                imm_src    = 3'b100; // U-type immediate
                result_src = 2'b00;  // write the ALU result...
                alu_src    = 1'b1;   // ...where ALU B input = immediate...
                alu_a_src  = 2'b10;  // ...and A input = 0
                alu_op     = 2'b00;  // ALU adds 0 + immediate = immediate
            end

            OP_AUIPC: begin
                reg_write  = 1'b1;
                imm_src    = 3'b100; // U-type immediate
                result_src = 2'b00;  // write the ALU result...
                alu_src    = 1'b1;   // ...where ALU B input = immediate...
                alu_a_src  = 2'b01;  // ...and A input = pc
                alu_op     = 2'b00;  // ALU adds pc + immediate
            end

            default: begin
                // Unknown opcode (covers FENCE/ECALL/EBREAK and anything
                // else this beginner CPU doesn't implement): decode as a
                // no-op so the CPU keeps running instead of corrupting state.
            end
        endcase
    end

endmodule
