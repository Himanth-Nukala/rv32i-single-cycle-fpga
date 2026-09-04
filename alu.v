// alu.v -- 32-bit ALU for the single-cycle RV32I datapath.
//
// This is the same "one big case statement on a control code" ALU pattern
// from Project 1's Task 5/6, just widened to 32 bits and with the extra
// operations RV32I needs (shifts, signed/unsigned less-than).
//
// alu_control encoding (chosen to match alu_decoder.v):
//   0000 = ADD   0001 = SUB    0010 = AND    0011 = OR
//   0100 = XOR   0101 = SLL    0110 = SRL    0111 = SRA
//   1000 = SLT   1001 = SLTU
module alu (
    input      [31:0] a,
    input      [31:0] b,
    input      [3:0]  alu_control,
    output reg [31:0] result,
    output             zero        // result == 0 -- used for BEQ/BNE
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

    // Shift amount is only the low 5 bits of b -- a 32-bit register can only
    // ever be shifted by 0-31 places.
    wire [4:0] shamt = b[4:0];

    always @(*) begin
        case (alu_control)
            ALU_ADD:  result = a + b;
            ALU_SUB:  result = a - b;
            ALU_AND:  result = a & b;
            ALU_OR:   result = a | b;
            ALU_XOR:  result = a ^ b;
            ALU_SLL:  result = a << shamt;
            ALU_SRL:  result = a >> shamt;
            ALU_SRA:  result = $signed(a) >>> shamt;
            // SLT: signed compare -- 1 if a < b, 0 otherwise
            ALU_SLT:  result = { 31'd0, $signed(a) < $signed(b) };
            // SLTU: unsigned compare -- 1 if a < b, 0 otherwise
            ALU_SLTU: result = { 31'd0, a < b };
            default:  result = 32'd0;
        endcase
    end

    assign zero = (result == 32'd0);

endmodule
