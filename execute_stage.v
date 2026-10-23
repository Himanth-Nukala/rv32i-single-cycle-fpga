// execute_stage.v -- the Execute stage: the ALU and the branch comparator,
// plus the small ALU-input muxes and the branch/jump target adder. See
// the course book's Task 11 for why branch_comp is a separate module from
// the ALU, and why the target adder runs every cycle, not just on branches.
module execute_stage (
    input      [31:0] pc,
    input      [31:0] rs1_data,
    input      [31:0] rs2_data,
    input      [31:0] imm_ext,
    input             alu_src,
    input      [1:0]  alu_a_src,
    input      [3:0]  alu_control,
    input      [2:0]  funct3,

    output     [31:0] alu_result,
    output            branch_taken,
    output     [31:0] pc_target
);

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
    wire        alu_zero;   // unused -- branch_comp handles all branch conditions

    alu u_alu (
        .a           (alu_src_a),
        .b           (alu_src_b),
        .alu_control (alu_control),
        .result      (alu_result),
        .zero        (alu_zero)
    );

    branch_comp u_branch_comp (
        .rs1_data (rs1_data),
        .rs2_data (rs2_data),
        .funct3   (funct3),
        .taken    (branch_taken)
    );

    // Separate adder for branch/JAL targets, computed every cycle in
    // parallel with the ALU so it's ready the instant branch_comp says
    // "taken," costing no extra cycle.
    assign pc_target = pc + imm_ext;

endmodule
