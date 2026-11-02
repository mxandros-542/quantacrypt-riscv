/* SPDX-License-Identifier: MIT */
#include "platform.h"
#if !defined(MLDSA44_IBEX)
#include <stdio.h>
#endif

static void demo_putchar(char c) {
#if defined(MLDSA44_IBEX)
  *(volatile uint32_t *)(uintptr_t)0x00020000u = (uint32_t)(unsigned char)c;
#else
  putchar((unsigned char)c);
#endif
}

void demo_puts(const char *text) {
  while (*text != '\0') demo_putchar(*text++);
}

void demo_hex32(uint32_t value) {
  static const char digits[] = "0123456789abcdef";
  for (int shift = 28; shift >= 0; shift -= 4)
    demo_putchar(digits[(value >> shift) & 15u]);
}

void demo_hex64(uint64_t value) {
  demo_puts("0x");
  demo_hex32((uint32_t)(value >> 32));
  demo_hex32((uint32_t)value);
}

uint64_t demo_cycles(void) {
#if defined(MLDSA44_IBEX)
  uint32_t high_before, low, high_after;
  /* RV32 needs the high/low/high sequence to handle a low-word rollover. */
  do {
    __asm__ volatile("csrr %0, mcycleh" : "=r"(high_before) :: "memory");
    __asm__ volatile("csrr %0, mcycle" : "=r"(low) :: "memory");
    __asm__ volatile("csrr %0, mcycleh" : "=r"(high_after) :: "memory");
  } while (high_before != high_after);
  return ((uint64_t)high_after << 32) | low;
#else
  return 0;
#endif
}
