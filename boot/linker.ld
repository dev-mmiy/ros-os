ENTRY(_start)
SECTIONS {
  . = 0x40080000;          /* QEMU virt DDR region */
  .text : { *(.text*) }
  .rodata : { *(.rodata*) }
  .data : { *(.data*) }
  .bss  : { *(.bss*) *(COMMON) }
}
