// imm_gen.v -- extracts and sign-extends the immediate embedded in an
// instruction word, based on which of RV32I's five immediate formats it is.
//
// RISC-V deliberately scrambles the immediate bits across the instruction
// word (rather than keeping them contiguous) so that rs1/rs2/rd/opcode/
// funct3 always sit in the exact same bit positions across every format --
// that's what lets reg_file and the decoders stay this simple. imm_gen is
// where that trade-off is paid back: it's the one module whose whole job is
// reassembling those scattered bits into an ordinary sign-extended 32-bit
// number.
module imm_gen (
    input      [31:0] instr,
    input      [2:0]  imm_src,
    output reg [31:0] imm_ext
);

    always @(*) begin
        case (imm_src)
            // I-type: ADDI, loads, JALR -- imm[11:0] = instr[31:20]
            3'b000: imm_ext = { {20{instr[31]}}, instr[31:20] };

            // S-type: stores -- imm[11:5] = instr[31:25], imm[4:0] = instr[11:7]
            3'b001: imm_ext = { {20{instr[31]}}, instr[31:25], instr[11:7] };

            // B-type: branches -- imm[12|10:5|4:1|11], bit 0 is always 0
            // (branch targets are always 2-byte aligned, so that bit isn't stored)
            3'b010: imm_ext = { {19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0 };

            // J-type: JAL -- imm[20|10:1|11|19:12], bit 0 is always 0
            3'b011: imm_ext = { {11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0 };

            // U-type: LUI, AUIPC -- imm[31:12] = instr[31:12], low 12 bits are 0
            3'b100: imm_ext = { instr[31:12], 12'd0 };

            default: imm_ext = 32'd0;
        endcase
    end

endmodule
