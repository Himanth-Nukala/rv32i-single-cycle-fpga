#!/usr/bin/env python3
"""
Independent reference model for cpu_test.s's 41 checkpoints.

Exactly like task-06's `expected_result` task in the ALU testbench, this is
a deliberately SEPARATE piece of code from both the assembly program and
the CPU's RTL -- it recomputes each checkpoint's expected value using
Python's own arithmetic, so it can catch a real bug in either the assembly
program's intent or the CPU's implementation, rather than just agreeing
with whichever one is wrong.

Run this, then feed the resulting expected.hex to tb_riscv_top.v via
$readmemh, exactly the same file-based-stimulus pattern Task 11 formalized.
"""
import sys


def u32(x):
    return x & 0xFFFFFFFF


def s32(x):
    x = u32(x)
    return x - (1 << 32) if x & 0x80000000 else x


# --- shared operands, matching cpu_test.s exactly ---
A = 5     # x5
B = -3    # x6  (0xFFFFFFFD)

checkpoints = []


def chk(value, note):
    checkpoints.append((u32(value), note))


# Section 1: I-type ALU-immediate
chk(A, "addi x5, x0, 5")
chk(B, "addi x6, x0, -3")
chk(A & 3, "andi x7, x5, 3")
chk(A | 2, "ori x8, x5, 2")
chk(A ^ 3, "xori x9, x5, 3")
chk(1 if B < 0 else 0, "slti x10, x6, 0")
chk(1 if u32(B) < 5 else 0, "sltiu x11, x6, 5")
chk(u32(A << 2), "slli x12, x5, 2")
chk(u32(B) >> 4, "srli x13, x6, 4  (logical)")
chk(u32(B >> 4), "srai x14, x6, 4  (arithmetic, Python >> on negative int already is arithmetic)")

# Section 2: R-type ALU
chk(A + B, "add x15, x5, x6")
chk(A - B, "sub x16, x5, x6")
chk(A & (A | 2), "and x17, x5, x8")
chk(A | (A ^ 3), "or x18, x5, x9")
chk(A ^ (A ^ 3), "xor x19, x5, x9")
chk(u32(A << (A & 3)), "sll x20, x5, x7   (x7 = 1)")
chk(u32(B) >> (A & 3), "srl x21, x6, x7   (logical, x7 = 1)")
chk(B >> (A & 3), "sra x22, x6, x7   (arithmetic, x7 = 1)")
chk(1 if B < A else 0, "slt x23, x6, x5")
chk(1 if u32(B) < u32(A) else 0, "sltu x24, x6, x5")

# Section 3: U-type
chk(0x12345000, "lui x25, 0x12345")
AUIPC_PC = 256  # byte address of the auipc instruction -- see asm/find_auipc_pc.py
chk(AUIPC_PC + (1 << 12), "auipc x26, 1")

# Section 4: Loads/stores
STORE_VAL = -86  # x28
chk(STORE_VAL, "lw x29, 0(x27)  -- full word read back")
byte0 = u32(STORE_VAL) & 0xFF          # low byte actually stored by `sw`
byte0_signed = (byte0 - 256) if (byte0 & 0x80) else byte0   # sign-extend an 8-bit value
chk(byte0_signed, "lb x29, 0(x27)  -- sign-extended byte")
chk(byte0, "lbu x29, 0(x27)  -- zero-extended byte")
HALF_VAL = 683  # x30, fits in 12 bits so no sign-extension surprises
chk(HALF_VAL, "lh x31, 8(x27)  -- sign-extended halfword")
chk(HALF_VAL, "lhu x31, 8(x27)  -- zero-extended halfword")

# Section 5: Branches -- every "taken" checkpoint expects 101, every
# "not-taken" checkpoint expects 201 (see cpu_test.s for why).
for _ in range(6):
    chk(101, "branch taken")
    chk(201, "branch not taken")

# Section 6: JAL/JALR call+return
chk(1, "x20 after returning to call_site")
chk(1, "x21 inside subroutine")


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else "expected.hex"
    with open(out_path, "w") as f:
        for value, note in checkpoints:
            f.write(f"{value:08x}  // {note}\n")
    print(f"Wrote {len(checkpoints)} expected checkpoint values -> {out_path}")


if __name__ == "__main__":
    main()
