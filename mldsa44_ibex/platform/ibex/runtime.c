/* SPDX-License-Identifier: MIT */
#include <stddef.h>
#include <stdint.h>
#include "platform.h"

/* Compiler-generated aggregate copies may call these in freestanding code. */
void *memcpy(void *restrict destination, const void *restrict source, size_t n) {
  unsigned char *dst = destination;
  const unsigned char *src = source;
  for (size_t i = 0; i < n; ++i) dst[i] = src[i];
  return destination;
}

void *memset(void *destination, int value, size_t n) {
  unsigned char *dst = destination;
  for (size_t i = 0; i < n; ++i) dst[i] = (unsigned char)value;
  return destination;
}

__attribute__((noreturn)) void ibex_finish(int status) {
  if (status != 0) demo_puts("PROGRAM FAILED\n");
  *(volatile uint32_t *)(uintptr_t)0x00020008u = 1u;
  for (;;) __asm__ volatile("wfi");
}

__attribute__((noreturn)) void ibex_trap(uint32_t cause, uint32_t pc) {
  demo_puts("TRAP: mcause=0x"); demo_hex32(cause);
  demo_puts(" mepc=0x"); demo_hex32(pc); demo_puts("\n");
  ibex_finish(1);
}
