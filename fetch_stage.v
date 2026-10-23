// fetch_stage.v -- the Fetch stage: PC register, instruction ROM, and the
// next-PC mux. See the course book's Task 11 for the full next-PC truth
// table and why the branch/jump target arrives from the Execute stage.
module fetch_stage #(
    parameter IMEM_FILE  = "hello_uart.hex",
    parameter IMEM_WORDS = 256
)(
    input             clk,
    input             rst_n,

    // control, from Decode
    input             jump,
    input             jalr,
    input             branch,

    // targets, from Execute
    input             branch_taken,
    input      [31:0] alu_result,
    input      [31:0] pc_target,

    output     [31:0] pc,
    output     [31:0] instr,
    output     [31:0] pc_plus4
);

    wire [31:0] pc_next;

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
