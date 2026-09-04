#!/usr/bin/env python3
"""
A tiny, two-pass RV32I assembler.

This is NOT a general-purpose tool -- it exists to generate the .hex
program files that instr_mem.v loads with $readmemh, for the demo program
and the testbench used in Project 4 of the FPGA course. It supports exactly
the base RV32I instructions this project's CPU implements, plus a handful
of the standard pseudo-instructions (nop, li, mv, j, ret) that expand to
one or two real instructions.

Usage:
    python assembler.py program.s program.hex

Output format: one 8-hex-digit instruction per line, in program order --
exactly what Verilog's $readmemh expects for a `reg [31:0] rom [...]` array.
"""
import re
import sys

REGS = {}
for i in range(32):
    REGS[f"x{i}"] = i
ABI = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7,
    "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15, "a6": 16, "a7": 17,
    "s2": 18, "s3": 19, "s4": 20, "s5": 21, "s6": 22, "s7": 23, "s8": 24, "s9": 25,
    "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
}
REGS.update(ABI)


def reg(name):
    name = name.strip().rstrip(",")
    if name not in REGS:
        raise ValueError(f"unknown register '{name}'")
    return REGS[name]


def imm(tok, labels=None, pc=None):
    tok = tok.strip().rstrip(",")
    if labels is not None and tok in labels:
        return labels[tok] - pc
    neg = tok.startswith("-")
    if neg:
        tok = tok[1:]
    val = int(tok, 0)
    return -val if neg else val


def s32(x):
    return x & 0xFFFFFFFF


def bits(val, hi, lo):
    """Extract val[hi:lo] (val may be negative -- treated as 32-bit two's complement)."""
    v = val & 0xFFFFFFFF
    width = hi - lo + 1
    return (v >> lo) & ((1 << width) - 1)


# ---------------------------------------------------------------------
# Encoders for each RV32I instruction format
# ---------------------------------------------------------------------
def enc_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_i(imm12, rs1, funct3, rd, opcode):
    return (bits(imm12, 11, 0) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_s(imm12, rs2, rs1, funct3, opcode):
    return (bits(imm12, 11, 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (bits(imm12, 4, 0) << 7) | opcode


def enc_b(imm13, rs2, rs1, funct3, opcode):
    return (bits(imm13, 12, 12) << 31) | (bits(imm13, 10, 5) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (bits(imm13, 4, 1) << 8) | (bits(imm13, 11, 11) << 7) | opcode


def enc_u(imm20, rd, opcode):
    # imm20 here is the raw upper-20-bits value (already positioned as if << 12 removed)
    return (bits(imm20, 19, 0) << 12) | (rd << 7) | opcode


def enc_j(imm21, rd, opcode):
    return (bits(imm21, 20, 20) << 31) | (bits(imm21, 10, 1) << 21) | (bits(imm21, 11, 11) << 20) | \
           (bits(imm21, 19, 12) << 12) | (rd << 7) | opcode


OPCODES = {
    "R": 0b0110011, "I": 0b0010011, "LOAD": 0b0000011, "STORE": 0b0100011,
    "BRANCH": 0b1100011, "JAL": 0b1101111, "JALR": 0b1100111,
    "LUI": 0b0110111, "AUIPC": 0b0010111,
}

R_TYPE = {
    # mnemonic: (funct7, funct3)
    "add":  (0b0000000, 0b000), "sub": (0b0100000, 0b000),
    "sll":  (0b0000000, 0b001), "slt": (0b0000000, 0b010), "sltu": (0b0000000, 0b011),
    "xor":  (0b0000000, 0b100),
    "srl":  (0b0000000, 0b101), "sra": (0b0100000, 0b101),
    "or":   (0b0000000, 0b110), "and": (0b0000000, 0b111),
}
I_ALU = {
    # mnemonic: funct3 (shifts also need a fixed funct7-style top bits, handled specially)
    "addi": 0b000, "slti": 0b010, "sltiu": 0b011, "xori": 0b100,
    "ori": 0b110, "andi": 0b111,
}
I_SHIFT = {"slli": (0b0000000, 0b001), "srli": (0b0000000, 0b101), "srai": (0b0100000, 0b101)}
LOADS = {"lb": 0b000, "lh": 0b001, "lw": 0b010, "lbu": 0b100, "lhu": 0b101}
STORES = {"sb": 0b000, "sh": 0b001, "sw": 0b010}
BRANCHES = {"beq": 0b000, "bne": 0b001, "blt": 0b100, "bge": 0b101, "bltu": 0b110, "bgeu": 0b111}


def split_mem_operand(tok):
    """'offset(reg)' -> (offset:int, reg:str)"""
    m = re.match(r"\s*(-?\w+)\((\w+)\)\s*", tok)
    if not m:
        raise ValueError(f"expected 'offset(reg)', got '{tok}'")
    return int(m.group(1), 0), m.group(2)


def strip_comment(line):
    for c in (";", "#", "//"):
        idx = line.find(c)
        if idx != -1:
            line = line[:idx]
    return line.strip()


def tokenize(line):
    line = line.replace(",", " , ")
    return [t for t in re.split(r"[\s,]+", line) if t]


def expand_pseudo(mnemonic, args):
    """Return a list of (mnemonic, args) real instructions for pseudo-ops."""
    if mnemonic == "nop":
        return [("addi", ["x0", "x0", "0"])]
    if mnemonic == "mv":
        return [("addi", [args[0], args[1], "0"])]
    if mnemonic == "j":
        return [("jal", ["x0", args[0]])]
    if mnemonic == "ret":
        return [("jalr", ["x0", "0(x1)"])]
    if mnemonic == "li":
        rd, val = args[0], int(args[1], 0)
        val &= 0xFFFFFFFF
        signed_val = val - 0x100000000 if val >= 0x80000000 else val
        if -2048 <= signed_val <= 2047:
            # Fits directly in a 12-bit signed immediate -- one instruction.
            return [("addi", [rd, "x0", str(signed_val)])]
        # Otherwise: LUI sets the top 20 bits, ADDI adds a signed 12-bit
        # correction. Because ADDI sign-extends its immediate, if the low
        # 12 bits look negative (bit 11 set) LUI must supply one extra 0x1000
        # in the top 20 bits to compensate, or the two additions won't add
        # back up to `val`.
        lo12 = val & 0xFFF
        lo12_signed = lo12 - 0x1000 if lo12 & 0x800 else lo12
        hi20 = ((val - (lo12_signed & 0xFFFFFFFF)) & 0xFFFFFFFF) >> 12
        insns = [("lui", [rd, str(hi20)])]
        if lo12_signed != 0:
            insns.append(("addi", [rd, rd, str(lo12_signed)]))
        return insns
    return [(mnemonic, args)]


def assemble(lines):
    # ---- Pass 1: expand pseudo-ops, strip comments/labels, record addresses ----
    expanded = []  # list of (mnemonic, args)
    labels = {}
    pc = 0
    for raw in lines:
        line = strip_comment(raw)
        if not line:
            continue
        # A line may start with "label:" before the instruction
        while ":" in line:
            label, _, rest = line.partition(":")
            labels[label.strip()] = pc
            line = rest.strip()
            if not line:
                break
        if not line:
            continue
        toks = tokenize(line)
        mnemonic = toks[0].lower()
        args = toks[1:]
        for real_mnemonic, real_args in expand_pseudo(mnemonic, args):
            expanded.append((real_mnemonic, real_args))
            pc += 4

    # ---- Pass 2: encode, now that every label's address is known ----
    words = []
    pc = 0
    for mnemonic, args in expanded:
        words.append(encode(mnemonic, args, pc, labels))
        pc += 4
    return words


def encode(mnemonic, args, pc, labels):
    if mnemonic in R_TYPE:
        f7, f3 = R_TYPE[mnemonic]
        rd, rs1, rs2 = reg(args[0]), reg(args[1]), reg(args[2])
        return enc_r(f7, rs2, rs1, f3, rd, OPCODES["R"])

    if mnemonic in I_ALU:
        f3 = I_ALU[mnemonic]
        rd, rs1 = reg(args[0]), reg(args[1])
        i = imm(args[2], labels, pc)
        return enc_i(i, rs1, f3, rd, OPCODES["I"])

    if mnemonic in I_SHIFT:
        f7, f3 = I_SHIFT[mnemonic]
        rd, rs1 = reg(args[0]), reg(args[1])
        shamt = imm(args[2], labels, pc) & 0x1F
        return enc_i((f7 << 5) | shamt, rs1, f3, rd, OPCODES["I"])

    if mnemonic in LOADS:
        f3 = LOADS[mnemonic]
        rd = reg(args[0])
        off, rs1name = split_mem_operand(args[1])
        return enc_i(off, reg(rs1name), f3, rd, OPCODES["LOAD"])

    if mnemonic in STORES:
        f3 = STORES[mnemonic]
        rs2 = reg(args[0])
        off, rs1name = split_mem_operand(args[1])
        return enc_s(off, rs2, reg(rs1name), f3, OPCODES["STORE"])

    if mnemonic in BRANCHES:
        f3 = BRANCHES[mnemonic]
        rs1, rs2 = reg(args[0]), reg(args[1])
        off = imm(args[2], labels, pc)
        return enc_b(off, rs2, rs1, f3, OPCODES["BRANCH"])

    if mnemonic == "jal":
        rd = reg(args[0])
        off = imm(args[1], labels, pc)
        return enc_j(off, rd, OPCODES["JAL"])

    if mnemonic == "jalr":
        rd = reg(args[0])
        off, rs1name = split_mem_operand(args[1])
        return enc_i(off, reg(rs1name), 0b000, rd, OPCODES["JALR"])

    if mnemonic == "lui":
        rd = reg(args[0])
        return enc_u(imm(args[1], labels, pc), rd, OPCODES["LUI"])

    if mnemonic == "auipc":
        rd = reg(args[0])
        return enc_u(imm(args[1], labels, pc), rd, OPCODES["AUIPC"])

    raise ValueError(f"unknown instruction '{mnemonic}'")


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    src_path, hex_path = sys.argv[1], sys.argv[2]
    with open(src_path) as f:
        lines = f.readlines()
    words = assemble(lines)
    with open(hex_path, "w") as f:
        for w in words:
            f.write(f"{s32(w):08x}\n")
    print(f"Assembled {len(words)} instructions -> {hex_path}")


if __name__ == "__main__":
    main()
