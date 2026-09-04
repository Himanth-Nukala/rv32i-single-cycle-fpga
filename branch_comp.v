// branch_comp.v -- decides whether a branch instruction is actually taken.
//
// Kept separate from the ALU on purpose: the ALU is busy (its A/B inputs
// are wired to rs1/rs2 for branches too, computing rs1-rs2 so its `zero`
// flag can serve BEQ/BNE), but BLT/BGE/BLTU/BGEU need both a *signed* and
// an *unsigned* comparison, not just subtraction. Rather than overload the
// ALU's op codes with branch-only variants, this small combinational block
// looks at rs1, rs2 and funct3 directly and produces one bit: taken or not.
module branch_comp (
    input      [31:0] rs1_data,
    input      [31:0] rs2_data,
    input      [2:0]  funct3,   // instr[14:12] -- selects which branch
    output reg        taken
);

    always @(*) begin
        case (funct3)
            3'b000: taken = (rs1_data == rs2_data);                     // BEQ
            3'b001: taken = (rs1_data != rs2_data);                     // BNE
            3'b100: taken = ($signed(rs1_data) <  $signed(rs2_data));   // BLT
            3'b101: taken = ($signed(rs1_data) >= $signed(rs2_data));   // BGE
            3'b110: taken = (rs1_data <  rs2_data);                     // BLTU
            3'b111: taken = (rs1_data >= rs2_data);                     // BGEU
            default: taken = 1'b0;
        endcase
    end

endmodule
