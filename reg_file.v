// reg_file.v -- the 32 general-purpose registers x0-x31.
//
// Two things make this different from an ordinary memory array:
//   1. x0 is hardwired to zero. RISC-V spends no storage on it -- reads of
//      register 0 always return 0, and writes to register 0 are silently
//      discarded. Software relies on this (it's how `mv rd, rs` becomes
//      `addi rd, rs, 0`, and how branches compare against a real zero).
//   2. Reads are combinational (asynchronous) and writes are synchronous.
//      A single-cycle CPU decodes, reads its operands, computes, and writes
//      back all within one clock period, so the read ports can't wait for
//      a clock edge -- they must reflect whatever `we3` last wrote
//      immediately.
module reg_file (
    input         clk,
    input         we3,          // write enable for port 3 (rd)
    input  [4:0]  a1,           // read address 1 (rs1)
    input  [4:0]  a2,           // read address 2 (rs2)
    input  [4:0]  a3,           // write address (rd)
    input  [31:0] wd3,          // write data
    output [31:0] rd1,          // read data 1 (rs1's value)
    output [31:0] rd2           // read data 2 (rs2's value)
);

    reg [31:0] registers [0:31];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            registers[i] = 32'd0;
    end

    // Asynchronous, "read-through-zero" reads: x0 always reads as 0 no
    // matter what (in case anything were ever accidentally written there).
    assign rd1 = (a1 == 5'd0) ? 32'd0 : registers[a1];
    assign rd2 = (a2 == 5'd0) ? 32'd0 : registers[a2];

    // Synchronous write, guarded so x0 can never actually be written.
    always @(posedge clk) begin
        if (we3 && (a3 != 5'd0))
            registers[a3] <= wd3;
    end

endmodule
