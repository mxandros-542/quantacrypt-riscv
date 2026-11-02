/* SPDX-License-Identifier: MIT */
#ifndef MLDSA44_DEMO_PLATFORM_H
#define MLDSA44_DEMO_PLATFORM_H
#include <stdint.h>
void demo_puts(const char *text);
void demo_hex32(uint32_t value);
void demo_hex64(uint64_t value);
uint64_t demo_cycles(void);
#endif
