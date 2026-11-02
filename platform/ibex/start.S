/* SPDX-License-Identifier: MIT
 * Ibex Simple System: vectors at 0x00100000, reset at base + 0x80.
 */
.section .vectors,"ax",@progbits
.option push
.option norvc
.global _vectors
_vectors:
.rept 32
  j trap_entry
.endr
.global _reset
_reset:
  j _start
.option pop

.section .text.start,"ax",@progbits
.global _start
_start:
  .option push
  .option norelax
  la gp, __global_pointer$
  .option pop
  la sp, __stack_top
  la t0, _vectors
  csrw mtvec, t0
  csrw mie, zero
  csrw mstatus, zero
  /* Enable mcycle/minstret; Ibex implements mcountinhibit at CSR 0x320. */
  csrw 0x320, zero
  la t0, __bss_start
  la t1, __bss_end
1:
  bgeu t0, t1, 2f
  sw zero, 0(t0)
  addi t0, t0, 4
  j 1b
2:
  call main
  tail ibex_finish

.align 2
trap_entry:
  /* A fresh stack lets the handler report even a stack-related exception. */
  la sp, __stack_top
  csrr a0, mcause
  csrr a1, mepc
  tail ibex_trap
