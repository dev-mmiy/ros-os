\
    .global _start
_start:
    // Assume EL1 on QEMU virt; set up a simple stack and call rust entry.
    ldr   x1, =_stack_top
    mov   sp, x1
    bl    rust_entry
1:  wfe
    b     1b

    .balign 16
    .global _stack_top
_stack:
    .space 0x4000
_stack_top:
