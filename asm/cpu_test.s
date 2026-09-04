# cpu_test.s -- one program that exercises every base RV32I instruction
# this CPU implements, and records a "checkpoint" result after each one.
#
# The technique: x2 is a moving pointer into data memory, starting at
# address 0. After each instruction (or short group of instructions) under
# test, we `sw` its result to `0(x2)` and then `addi x2, x2, 4` to advance
# to the next word. The result is a flat, in-order log of 32-bit values in
# data memory -- checkpoint 0 at address 0, checkpoint 1 at address 4, and
# so on -- that tb_riscv_top.v reads back and compares against an
# independently-computed expected.hex, using the exact same
# task-automatic/$readmemh/accumulate-errors pattern as every other
# self-checking testbench in this book.
#
# Register map for this program (all "scratch": nothing here is meant to
# survive past its own checkpoint):
#   x2            checkpoint pointer (never used for anything else)
#   x1             return-address register for the jal/jalr call+return test
#                  (this is the same job register x1 has in real RISC-V
#                  calling convention, where it's called `ra`)
#   x5-x31        general scratch, reused freely between sections

    addi x2, x0, 0          # x2 = checkpoint pointer = address 0

# =====================================================================
# Section 1: I-type ALU-immediate instructions
# =====================================================================
    addi x5, x0, 5           # x5 = 5                      [chk 0]
    sw   x5, 0(x2)
    addi x2, x2, 4

    addi x6, x0, -3          # x6 = -3                      [chk 1]
    sw   x6, 0(x2)
    addi x2, x2, 4

    andi x7, x5, 3            # x7 = 5 & 3 = 1                [chk 2]
    sw   x7, 0(x2)
    addi x2, x2, 4

    ori  x8, x5, 2             # x8 = 5 | 2 = 7                 [chk 3]
    sw   x8, 0(x2)
    addi x2, x2, 4

    xori x9, x5, 3              # x9 = 5 ^ 3 = 6                   [chk 4]
    sw   x9, 0(x2)
    addi x2, x2, 4

    slti x10, x6, 0               # x10 = (x6 <s 0) = (-3<0) = 1      [chk 5]
    sw   x10, 0(x2)
    addi x2, x2, 4

    sltiu x11, x6, 5                # x11 = (x6 <u 5) -- x6=-3 as unsigned is huge, so 0 [chk 6]
    sw   x11, 0(x2)
    addi x2, x2, 4

    slli x12, x5, 2                  # x12 = 5 << 2 = 20                  [chk 7]
    sw   x12, 0(x2)
    addi x2, x2, 4

    srli x13, x6, 4                   # x13 = logical (-3)>>4 = 0x0FFFFFFF [chk 8]
    sw   x13, 0(x2)
    addi x2, x2, 4

    srai x14, x6, 4                    # x14 = arithmetic (-3)>>4 = -1        [chk 9]
    sw   x14, 0(x2)
    addi x2, x2, 4

# =====================================================================
# Section 2: R-type ALU instructions
# =====================================================================
    add  x15, x5, x6          # x15 = 5 + (-3) = 2                [chk 10]
    sw   x15, 0(x2)
    addi x2, x2, 4

    sub  x16, x5, x6           # x16 = 5 - (-3) = 8                 [chk 11]
    sw   x16, 0(x2)
    addi x2, x2, 4

    and  x17, x5, x8            # x17 = 5 & 7 = 5                     [chk 12]
    sw   x17, 0(x2)
    addi x2, x2, 4

    or   x18, x5, x9             # x18 = 5 | 6 = 7                      [chk 13]
    sw   x18, 0(x2)
    addi x2, x2, 4

    xor  x19, x5, x9              # x19 = 5 ^ 6 = 3                       [chk 14]
    sw   x19, 0(x2)
    addi x2, x2, 4

    sll  x20, x5, x7               # x20 = 5 << (x7=1) = 10                 [chk 15]
    sw   x20, 0(x2)
    addi x2, x2, 4

    srl  x21, x6, x7                # x21 = logical (-3)>>1 = 0x7FFFFFFE       [chk 16]
    sw   x21, 0(x2)
    addi x2, x2, 4

    sra  x22, x6, x7                 # x22 = arithmetic (-3)>>1 = -2              [chk 17]
    sw   x22, 0(x2)
    addi x2, x2, 4

    slt  x23, x6, x5                  # x23 = (x6 <s x5) = (-3<5) = 1               [chk 18]
    sw   x23, 0(x2)
    addi x2, x2, 4

    sltu x24, x6, x5                   # x24 = (x6 <u x5) -- huge <u 5 = 0             [chk 19]
    sw   x24, 0(x2)
    addi x2, x2, 4

# =====================================================================
# Section 3: U-type instructions
# =====================================================================
    lui   x25, 0x12345         # x25 = 0x12345000                                [chk 20]
    sw    x25, 0(x2)
    addi  x2, x2, 4

    auipc x26, 1                 # x26 = pc(this instr) + (1<<12) = pc + 0x1000    [chk 21]
    sw    x26, 0(x2)
    addi  x2, x2, 4

# =====================================================================
# Section 4: Load/store instructions (word/half/byte, signed/unsigned)
# =====================================================================
    addi x27, x0, 500          # x27 = scratch data address (well clear of the checkpoint log)
    addi x28, x0, -86           # x28 = -86 (byte pattern 0xAA in its low byte)

    sw   x28, 0(x27)             # store word -86 at address 500

    lw   x29, 0(x27)              # x29 = -86, read back as a full word             [chk 22]
    sw   x29, 0(x2)
    addi x2, x2, 4

    lb   x29, 0(x27)              # x29 = sign-extend(0xAA) = -86                    [chk 23]
    sw   x29, 0(x2)
    addi x2, x2, 4

    lbu  x29, 0(x27)              # x29 = zero-extend(0xAA) = 170                     [chk 24]
    sw   x29, 0(x2)
    addi x2, x2, 4

    addi x30, x0, 683              # x30 = 0x02AB, a positive halfword-sized test value
    sh   x30, 8(x27)                 # store halfword 683 at address 508

    lh   x31, 8(x27)                  # x31 = sign-extend(0x02AB) = 683                  [chk 25]
    sw   x31, 0(x2)
    addi x2, x2, 4

    lhu  x31, 8(x27)                   # x31 = zero-extend(0x02AB) = 683                   [chk 26]
    sw   x31, 0(x2)
    addi x2, x2, 4

# =====================================================================
# Section 5: Branch instructions -- one "taken" and one "not-taken" test
# per condition. Pattern: set a marker to a base value, run the branch, and
# place a "corruption" instruction right after it that only executes if the
# branch's taken/not-taken decision was WRONG. The following label always
# does `marker = marker + 1`, so a correct branch produces `base+1`, while
# a broken one produces `corrupted+1` -- the two are never equal, so this
# catches the bug regardless of which direction it's wrong in.
#
# Comparison operands used throughout this section:
#   x5 = 5 (positive), x6 = -3 (negative; huge when read as unsigned)
# =====================================================================

    # --- BEQ, taken (x5 == x5) ---
    addi x8, x0, 100
    beq  x5, x5, beq_t_ok
    addi x8, x0, 900            # corruption: only runs if BEQ wrongly NOT taken
beq_t_ok:
    addi x8, x8, 1               # expect 101                                        [chk 27]
    sw   x8, 0(x2)
    addi x2, x2, 4

    # --- BEQ, not taken (x5 != x6) ---
    addi x8, x0, 200
    beq  x5, x6, beq_nt_ok
    addi x8, x8, 1                # fallthrough: only runs if BEQ correctly NOT taken
beq_nt_ok:
                                    # expect 201                                        [chk 28]
    sw   x8, 0(x2)
    addi x2, x2, 4

    # --- BNE, taken (x5 != x6) ---
    addi x8, x0, 100
    bne  x5, x6, bne_t_ok
    addi x8, x0, 900
bne_t_ok:
    addi x8, x8, 1                # expect 101                                        [chk 29]
    sw   x8, 0(x2)
    addi x2, x2, 4

    # --- BNE, not taken (x5 == x5) ---
    addi x8, x0, 200
    bne  x5, x5, bne_nt_ok
    addi x8, x8, 1
bne_nt_ok:
                                    # expect 201                                        [chk 30]
    sw   x8, 0(x2)
    addi x2, x2, 4

    # --- BLT, taken (x6 <s x5, i.e. -3 < 5) ---
    addi x8, x0, 100
    blt  x6, x5, blt_t_ok
    addi x8, x0, 900
blt_t_ok:
    addi x8, x8, 1                # expect 101                                        [chk 31]
    sw   x8, 0(x2)
    addi x2, x2, 4

    # --- BLT, not taken (x5 <s x6, i.e. 5 < -3 is false) ---
    addi x8, x0, 200
    blt  x5, x6, blt_nt_ok
    addi x8, x8, 1
blt_nt_ok:
                                    # expect 201                                        [chk 32]
    sw   x8, 0(x2)
    addi x2, x2, 4

    # --- BGE, taken (x5 >=s x6, i.e. 5 >= -3) ---
    addi x8, x0, 100
    bge  x5, x6, bge_t_ok
    addi x8, x0, 900
bge_t_ok:
    addi x8, x8, 1                # expect 101                                        [chk 33]
    sw   x8, 0(x2)
    addi x2, x2, 4

    # --- BGE, not taken (x6 >=s x5, i.e. -3 >= 5 is false) ---
    addi x8, x0, 200
    bge  x6, x5, bge_nt_ok
    addi x8, x8, 1
bge_nt_ok:
                                    # expect 201                                        [chk 34]
    sw   x8, 0(x2)
    addi x2, x2, 4

    # --- BLTU, taken (x5 <u x6, i.e. 5 <u huge) ---
    addi x8, x0, 100
    bltu x5, x6, bltu_t_ok
    addi x8, x0, 900
bltu_t_ok:
    addi x8, x8, 1                # expect 101                                        [chk 35]
    sw   x8, 0(x2)
    addi x2, x2, 4

    # --- BLTU, not taken (x6 <u x5, i.e. huge <u 5 is false) ---
    addi x8, x0, 200
    bltu x6, x5, bltu_nt_ok
    addi x8, x8, 1
bltu_nt_ok:
                                    # expect 201                                        [chk 36]
    sw   x8, 0(x2)
    addi x2, x2, 4

    # --- BGEU, taken (x6 >=u x5, i.e. huge >=u 5) ---
    addi x8, x0, 100
    bgeu x6, x5, bgeu_t_ok
    addi x8, x0, 900
bgeu_t_ok:
    addi x8, x8, 1                # expect 101                                        [chk 37]
    sw   x8, 0(x2)
    addi x2, x2, 4

    # --- BGEU, not taken (x5 >=u x6, i.e. 5 >=u huge is false) ---
    addi x8, x0, 200
    bgeu x5, x6, bgeu_nt_ok
    addi x8, x8, 1
bgeu_nt_ok:
                                    # expect 201                                        [chk 38]
    sw   x8, 0(x2)
    addi x2, x2, 4

# =====================================================================
# Section 6: JAL + JALR, as a real subroutine call and return -- exactly
# the `jal ra, func` / ... / `jalr x0, 0(ra)` pattern used for real RISC-V
# function calls, just with x1 standing in for `ra` explicitly.
# =====================================================================
    addi x20, x0, 0            # x20: proves we returned to call_site (starts at 0)
    addi x21, x0, 0             # x21: proves the subroutine body ran (starts at 0)

    jal  x1, subroutine          # x1 = return address (address of call_site below); jump into the subroutine
call_site:
    addi x20, x20, 1               # only reached by actually returning here          [chk 39]
    sw   x20, 0(x2)
    addi x2, x2, 4
    jal  x0, after_subroutine       # unconditionally skip over the subroutine body

subroutine:
    addi x21, x21, 1                 # proves the call landed exactly here            [chk 40]
    sw   x21, 0(x2)
    addi x2, x2, 4
    jalr x0, 0(x1)                    # return to call_site, using the saved address in x1

after_subroutine:

# =====================================================================
# Done -- park in an infinite self-loop. tb_riscv_top.v runs the CPU for a
# fixed number of cycles, comfortably more than this whole program needs,
# then simply stops the clock and checks the results -- it never depends on
# the CPU "signaling" completion.
# =====================================================================
done:
    jal x0, done
