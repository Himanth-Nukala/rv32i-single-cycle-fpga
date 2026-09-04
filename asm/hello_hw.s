# hello_hw.s -- the program actually flashed onto the DE0-Nano: same
# send_loop as hello.s, but wrapped in an outer loop so it prints the
# greeting forever, with a software delay between each print so a serial
# terminal shows a fresh line roughly every eighth of a second instead of
# an unreadable burst.
#
# Each delay-loop iteration is 2 instructions (an `addi` and a `bne`), so
# at the DE0-Nano's 50MHz clock (20ns/cycle, one cycle per instruction on
# this single-cycle CPU) N iterations take N * 40ns. 3,000,000 iterations
# -> 120ms between prints.

    addi a3, x0, 1024        # a3 = UART_BASE_ADDR (TX_DATA=1024, TX_STATUS=1028), set once

main:
    addi a0, x0, 0             # a0 = pointer to the start of the string

send_loop:
    lb   a1, 0(a0)
    beq  a1, x0, delay

wait_for_uart:
    lw   a2, 4(a3)
    andi a2, a2, 1
    bne  a2, x0, wait_for_uart

    sb   a1, 0(a3)
    addi a0, a0, 1
    jal  x0, send_loop

delay:
    li   t1, 3000000
delay_loop:
    addi t1, t1, -1
    bne  t1, x0, delay_loop

    jal  x0, main
