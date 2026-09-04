// data_mem.v -- byte-addressable RAM for loads and stores.
//
// RV32I's load/store instructions each move a different-sized chunk (byte,
// halfword, or word), and loads additionally choose between sign-extending
// and zero-extending that chunk back up to 32 bits. funct3 tells us which:
//
//   funct3   load          store
//   000      LB  (sign)    SB
//   001      LH  (sign)    SH
//   010      LW             SW
//   100      LBU (zero)     --
//   101      LHU (zero)     --
//
// The array itself is modeled byte-by-byte (`mem[byte_addr]`), which is
// what makes sub-word accesses straightforward: a byte load/store touches
// exactly one entry, a halfword touches two, a word touches four -- always
// starting at `addr`.
module data_mem #(
    parameter MEM_BYTES = 1024,  // 1KB of data RAM
    parameter MEM_FILE  = ""     // optional $readmemh file for initial contents (e.g. a string table)
)(
    input             clk,
    input      [31:0] addr,
    input      [31:0] write_data,
    input             mem_write,
    input      [2:0]  funct3,
    output reg [31:0] read_data
);

    reg [7:0] mem [0:MEM_BYTES-1];

    integer i;
    initial begin
        for (i = 0; i < MEM_BYTES; i = i + 1)
            mem[i] = 8'd0;
        if (MEM_FILE != "")
            $readmemh(MEM_FILE, mem);
    end

    // The CPU's address bus is a full 32-bit byte address (the same bus the
    // UART peripheral lives on, further up the address space), but this
    // array only has MEM_BYTES entries. Explicitly truncating to the bits
    // that actually index the array -- rather than handing raw `addr` to
    // Verilog and hoping the tool truncates it the same way in simulation
    // and synthesis -- keeps the two in agreement and keeps addresses that
    // belong to a *different* peripheral (like the UART registers) from
    // silently aliasing onto a real RAM location.
    localparam ADDR_BITS = $clog2(MEM_BYTES);
    wire [ADDR_BITS-1:0] a0 = addr[ADDR_BITS-1:0];
    wire [ADDR_BITS-1:0] a1 = a0 + 1'b1;
    wire [ADDR_BITS-1:0] a2 = a0 + 2'd2;
    wire [ADDR_BITS-1:0] a3 = a0 + 2'd3;

    // --- Writes (stores) -- synchronous, one clock edge, exactly the
    // number of bytes the instruction asked for. ---
    always @(posedge clk) begin
        if (mem_write) begin
            case (funct3)
                3'b000: begin // SB
                    mem[a0] <= write_data[7:0];
                end
                3'b001: begin // SH
                    mem[a0] <= write_data[7:0];
                    mem[a1] <= write_data[15:8];
                end
                3'b010: begin // SW
                    mem[a0] <= write_data[7:0];
                    mem[a1] <= write_data[15:8];
                    mem[a2] <= write_data[23:16];
                    mem[a3] <= write_data[31:24];
                end
                default: ; // ignore malformed stores
            endcase
        end
    end

    // --- Reads (loads) -- combinational, so the value is ready the same
    // cycle for result_src to forward into the register file. ---
    always @(*) begin
        case (funct3)
            3'b000: read_data = { {24{mem[a0][7]}}, mem[a0] };            // LB
            3'b001: read_data = { {16{mem[a1][7]}}, mem[a1], mem[a0] };   // LH
            3'b010: read_data = { mem[a3], mem[a2], mem[a1], mem[a0] };   // LW
            3'b100: read_data = { 24'd0, mem[a0] };                       // LBU
            3'b101: read_data = { 16'd0, mem[a1], mem[a0] };              // LHU
            default: read_data = 32'd0;
        endcase
    end

endmodule
