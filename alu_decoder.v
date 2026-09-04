// alu_decoder.v -- turns (alu_op, funct3, funct7b5) into the 4-bit code
// the ALU itself understands.
//
// This is kept as its own module, separate from main_decoder.v, because it
// answers a genuinely different question. main_decoder looks only at the
// opcode and asks "what KIND of instruction is this" (R-type ALU op,
// I-type ALU op, load, store, branch, ...). It produces a coarse 2-bit
// alu_op hint. alu_decoder then looks at funct3/funct7 -- fields that only
// make sense once you already know you're building an ALU operation -- to
// pick the exact operation.
//
// alu_op meaning (from main_decoder):
//   00 -> always ADD          (loads, stores, JAL/JALR address calc)
//   01 -> always SUB          (branches, so ALU produces a-b and 'zero' can
//                              be used for equality)
//   10 -> look at funct3/funct7 (R-type and I-type ALU instructions)
module alu_decoder (
    input      [1:0] alu_op,
    input      [2:0] funct3,
    input             funct7b5,   // instr[30] -- distinguishes ADD/SUB, SRL/SRA
    input             op5,        // instr[5]  -- 1 for R-type, 0 for I-type
    output reg [3:0] alu_control
);

    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLL  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_SLT  = 4'b1000;
    localparam ALU_SLTU = 4'b1001;

    // funct7b5 only selects SUB (instead of ADD) or SRA (instead of SRL)
    // when it's actually an R-type instruction. For I-type ALU instructions
    // (ADDI, SRLI/SRAI are the one exception -- see below), bit 30 of an
    // I-immediate is just part of the immediate, not a sub-opcode, EXCEPT
    // Quartus/RISC-V still uses instr[30] for SRLI vs SRAI, so we always
    // look at it for shifts specifically.
    wire is_sub_or_sra = funct7b5;

    always @(*) begin
        case (alu_op)
            2'b00: alu_control = ALU_ADD;   // loads/stores/JAL/JALR/AUIPC
            2'b01: alu_control = ALU_SUB;   // branches
            2'b10: begin
                case (funct3)
                    3'b000: alu_control = (is_sub_or_sra && op5) ? ALU_SUB : ALU_ADD; // ADD/ADDI or SUB
                    3'b001: alu_control = ALU_SLL;
                    3'b010: alu_control = ALU_SLT;
                    3'b011: alu_control = ALU_SLTU;
                    3'b100: alu_control = ALU_XOR;
                    3'b101: alu_control = is_sub_or_sra ? ALU_SRA : ALU_SRL;          // SRL/SRLI or SRA/SRAI
                    3'b110: alu_control = ALU_OR;
                    3'b111: alu_control = ALU_AND;
                    default: alu_control = ALU_ADD;
                endcase
            end
            default: alu_control = ALU_ADD;
        endcase
    end

endmodule
