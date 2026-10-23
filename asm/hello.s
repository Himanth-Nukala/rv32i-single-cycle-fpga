# hello.s -- the FPGA demo program: read a null-terminated string out of
# data memory, one byte at a time, and transmit each byte over UART,
# polling the TX_STATUS "busy" bit between characters so no byte is ever
# started before the previous one has finished shifting out.
#
# The string itself isn't in this file -- it's a separate ASCII payload
# (see gen_string_hex.py) preloaded into data memory starting at address 0
# via data_mem.v's DMEM_FILE parameter, exactly the same $readmemh
# separation-of-data-from-logic idea Task 8 taught for testbenches,
# just used here for a real program instead of test stimulus.
#
# a0 = pointer into the string (starts at address 0, the string's start)
# a1 = the character just read
# a2 = scratch for the UART status word
# a3 = UART peripheral's base address (TX_DATA register; TX_STATUS is +4)

    addi a0, x0, 0
    addi a3, x0, 1024        # 1024 = 0x400 = riscv_top's UART_BASE_ADDR

send_loop:
    lb   a1, 0(a0)              # a1 = the next character
    beq  a1, x0, halt            # a null byte marks the end of the string

wait_for_uart:
    lw   a2, 4(a3)                 # a2 = TX_STATUS (bit 0 = busy)
    andi a2, a2, 1
    bne  a2, x0, wait_for_uart      # keep polling while the UART is still busy

    sb   a1, 0(a3)                   # write the character -- this starts the transmit
    addi a0, a0, 1                    # advance to the next character
    jal  x0, send_loop

halt:
    jal x0, halt                       # done -- park here forever
