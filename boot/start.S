    .global _start
    .extern rust_entry
    .extern irq_entry_rust

    .align 11
vectors:
    // EL1向けの例外ベクタ
    b .          // Synchronous EL1t
    b irq_common // IRQ EL1t
    b .          // FIQ EL1t
    b .          // SError EL1t

    b .          // Synchronous EL1h
    b irq_common // IRQ EL1h
    b .          // FIQ EL1h
    b .          // SError EL1h

    b .          // Synchronous EL0_64
    b irq_common // IRQ EL0_64
    b .          // FIQ EL0_64
    b .          // SError EL0_64

    b .          // Synchronous EL0_32
    b irq_common // IRQ EL0_32
    b .          // FIQ EL0_32
    b .          // SError EL0_32

irq_common:
    // 最小限レジスタ退避
    sub sp, sp, #40
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    str x30, [sp, #32]

    bl irq_entry_rust

    ldr x30, [sp, #32]
    ldp x2, x3, [sp, #16]
    ldp x0, x1, [sp, #0]
    add sp, sp, #40
    eret

    .global _start
_start:
    // 現在のELを確認
    mrs x0, CurrentEL
    cmp x0, #0x8        // 0x8 = EL2, 0x4 = EL1
    b.ne 1f             // すでにEL1なら el1_entry へ

    // ===== EL2 → EL1h に降りる準備 =====
    // SP_EL1 を用意
    ldr   x1, =_stack_top
    msr   SP_EL1, x1

    // HCR_EL2 はデフォルト0でOK（仮想化オフ）
    mov   x1, #0
    msr   HCR_EL2, x1

    // EL1h で戻る設定（SPSR_EL2）
    // D,A,I,F は一旦マスク（後でRust側で解除）
    // M[3:0]=0101(EL1h)
    mov   x1, #0b0101
    mov   x2, #(1<<9) | (1<<8) | (1<<7) | (1<<6)   // D,A,I,F = 1
    orr   x1, x1, x2
    msr   SPSR_EL2, x1

    // 戻り先（EL1のエントリ）
    adr   x1, el1_entry
    msr   ELR_EL2, x1
    eret

1:  // ===== ここから EL1 =====
el1_entry:
    // スタック
    ldr   x1, =_stack_top
    mov   sp, x1

    // 例外ベクタ（EL1）
    ldr   x0, =vectors
    msr   VBAR_EL1, x0
    isb

    // ここから先は Rust に任せる（Rust側で DAIFClr してIRQ開放）
    bl    rust_entry
2:  wfe
    b     2b

    .balign 16
    .global _stack_top
_stack:
    .space 0x4000
_stack_top:
