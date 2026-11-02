/* SPDX-License-Identifier: MIT
 * Default matches the documented 1 MiB Ibex Simple System RAM.
 * Smaller FPGA systems must adjust RAM_BYTES and retain adequate stack space.
 */
OUTPUT_ARCH(riscv)
ENTRY(_reset)
RAM_BYTES = DEFINED(IBEX_RAM_BYTES) ? IBEX_RAM_BYTES : 0x100000;
STACK_BYTES = DEFINED(IBEX_STACK_BYTES) ? IBEX_STACK_BYTES : 0x20000;
MEMORY { ram (rwx) : ORIGIN = 0x00100000, LENGTH = RAM_BYTES }
PHDRS { code PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); }
SECTIONS {
  .vectors : { KEEP(*(.vectors)) } > ram :code
  .text : { *(.text.start) *(.text .text.*) } > ram :code
  .rodata : { *(.srodata .srodata.* .rodata .rodata.*) } > ram :code
  .data : {
    . = ALIGN(8);
    __global_pointer$ = . + 0x800;
    *(.sdata .sdata.* .data .data.*)
  } > ram :data
  .bss (NOLOAD) : {
    . = ALIGN(8);
    __bss_start = .;
    *(.sbss .sbss.* .bss .bss.* COMMON)
    . = ALIGN(8);
    __bss_end = .;
  } > ram :data
  __stack_top = (ORIGIN(ram) + LENGTH(ram)) & ~15;
  __stack_bottom = __stack_top - STACK_BYTES;
  /DISCARD/ : { *(.comment .note .note.* .eh_frame .eh_frame.*) }
}
ASSERT(ADDR(.vectors) == 0x00100000, "Ibex vector base mismatch")
ASSERT(_reset == 0x00100080, "Ibex reset address mismatch")
ASSERT(__bss_end <= __stack_bottom, "Program overlaps reserved stack")
ASSERT(STACK_BYTES >= 0x10000, "Reference ML-DSA needs at least 64 KiB reserved stack")
