#!/usr/bin/env python3
"""
Turns a string into a byte-per-line hex file for $readmemh -- the format
data_mem.v's `reg [7:0] mem [0:MEM_BYTES-1]` array expects: one 8-bit hex
value per line, in address order starting at 0.

Usage:
    python gen_string_hex.py "Hello, RISC-V!\\r\\n" hello_data.hex
"""
import sys


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    text, out_path = sys.argv[1], sys.argv[2]
    text = text.encode().decode("unicode_escape")  # let \r \n etc. work from the shell
    data = text.encode("ascii") + b"\x00"          # null terminator -- hello.s stops here
    with open(out_path, "w") as f:
        for b in data:
            f.write(f"{b:02x}\n")
    print(f"Wrote {len(data)} bytes -> {out_path}")


if __name__ == "__main__":
    main()
