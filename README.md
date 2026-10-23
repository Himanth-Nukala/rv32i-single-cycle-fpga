# RV32I Single-Cycle Processor (DE0-Nano / Cyclone IV)

A single-cycle RISC-V RV32I processor, written in Verilog, verified in simulation against every base instruction it implements, and running on a real Terasic DE0-Nano (Altera/Intel Cyclone IV `EP4CE22F17C6`) — where it prints `"Hello, RISC-V!"` over UART, from its own assembly program, forever.

This is Project 4 of the [e-Yantra FPGA Design with Verilog](https://github.com/Himanth-Nukala/fpga-alu-mdbook) course. **The course book is the full walkthrough** — instruction formats, every module explained, the testbench methodology, the real FPGA-fitting problem this project hit and how it was diagnosed and fixed, and how to flash and read the output yourself. This repository is the buildable, runnable source code that walkthrough is based on.

## What's here

| File | Role |
|---|---|
| `program_counter.v` | PC register |
| `instr_mem.v` | Instruction ROM, `$readmemh`-loaded |
| `main_decoder.v` | Opcode → control signals |
| `alu_decoder.v` | funct3/funct7 → exact ALU operation |
| `reg_file.v` | 32×32 register file, `x0` hardwired to 0 |
| `imm_gen.v` | I/S/B/U/J immediate decoding |
| `alu.v` | ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU |
| `branch_comp.v` | BEQ/BNE/BLT/BGE/BLTU/BGEU |
| `data_mem.v` | Byte-addressable RAM, LB/LH/LW/LBU/LHU + SB/SH/SW |
| `uart_tx.v` | 8N1 UART transmitter |
| `uart_mmio.v` | Memory-mapped UART peripheral (`sw` to send, `lw` to poll busy) |
| `fetch_stage.v` | Fetch stage wrapper: `program_counter.v` + `instr_mem.v` + the next-PC mux |
| `decode_stage.v` | Decode stage wrapper: `main_decoder.v` + `alu_decoder.v` + `reg_file.v` + `imm_gen.v` |
| `execute_stage.v` | Execute stage wrapper: `alu.v` + `branch_comp.v` + the branch/jump target adder |
| `memory_stage.v` | Memory stage wrapper: `data_mem.v` + `uart_mmio.v` |
| `riscv_top.v` | Wires the four stage modules together, plus the write-back mux |
| `riscv_fpga_top.v` / `.qpf` / `.qsf` / `.sld` | DE0-Nano top level + Quartus project |
| `tb_riscv_top.v` | Self-checking testbench — 41 checkpoints covering every implemented RV32I instruction except `sb` (which the UART testbenches exercise) |
| `tb_hello_uart.v`, `tb_hello_hw_repeat.v` | End-to-end UART output testbenches |
| `asm/assembler.py` | A small two-pass RV32I assembler (this project's own toolchain) |
| `asm/gen_expected.py` | Independent Python reference model for the testbench's expected values |
| `asm/cpu_test.s`, `asm/hello.s`, `asm/hello_hw.s` | The assembly programs this project runs |
| `*.hex` | Assembled programs / data, loaded by `$readmemh` |

Implements every RV32I base instruction except `FENCE`/`ECALL`/`EBREAK`, which decode as no-ops — see the course book for why that scope was chosen.

## Running the testbench

Requires [Icarus Verilog](http://iverilog.icarus.com/) (or ModelSim-Altera, included with Quartus Prime Lite):

```sh
iverilog -g2005 -o tb.vvp -s tb_riscv_top \
    alu.v alu_decoder.v main_decoder.v reg_file.v imm_gen.v branch_comp.v \
    program_counter.v instr_mem.v data_mem.v uart_tx.v uart_mmio.v \
    fetch_stage.v decode_stage.v execute_stage.v memory_stage.v riscv_top.v \
    tb_riscv_top.v
vvp tb.vvp
```

Each checkpoint prints one line naming its instruction, for example `[PASS] checkpoint  4  xori x9, x5, 3        0x00000006`. The run ends with: `RV32I CPU testbench PASSED all 41 checkpoints.`

## Building for hardware

Requires Intel Quartus Prime Lite (this was built and flashed with 20.1.1):

```sh
quartus_map riscv_fpga_top
quartus_fit riscv_fpga_top
quartus_asm riscv_fpga_top
quartus_pgm -c "USB-Blaster [USB-0]" -m JTAG -o "p;riscv_fpga_top.sof"
```

Wire a USB-to-TTL adapter's `TXD`/`RXD` to the DE0-Nano's `GPIO_0` pins `D3`/`C3` (cross-connected), open a serial terminal at 115200 8N1, and you should see `Hello, RISC-V!` printed roughly every eighth of a second.

## License

MIT
