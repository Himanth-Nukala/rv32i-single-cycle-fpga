// program_counter.v -- the PC register.
//
// The simplest sequential element in the whole CPU: on every clock edge,
// it latches whatever riscv_top.v's next-PC mux computed last cycle. Reset
// forces it back to address 0, where instr_mem.v's program always begins.
module program_counter (
    input             clk,
    input             rst_n,
    input      [31:0] pc_next,
    output reg [31:0] pc
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= 32'd0;
        else
            pc <= pc_next;
    end

endmodule
