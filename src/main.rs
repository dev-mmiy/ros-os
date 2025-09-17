\
#![no_std]
#![no_main]

use core::panic::PanicInfo;

// PL011 UART @ 0x0900_0000 (QEMU virt)
const UART0_BASE: usize = 0x0900_0000;
const DR:    usize = UART0_BASE + 0x00;
const FR:    usize = UART0_BASE + 0x18;
const TXFF:  u32   = 1 << 5;

#[inline(always)]
fn mmio_write(addr: usize, val: u32) {
    unsafe { core::ptr::write_volatile(addr as *mut u32, val) }
}
#[inline(always)]
fn mmio_read(addr: usize) -> u32 {
    unsafe { core::ptr::read_volatile(addr as *const u32) }
}

fn uart_putc(c: u8) {
    while (mmio_read(FR) & TXFF) != 0 {}
    mmio_write(DR, c as u32);
}
fn uart_puts(s: &str) {
    for b in s.bytes() {
        if b == bn { uart_putc(br); }
        uart_putc(b);
    }
}

#[no_mangle]
pub extern "C" fn rust_entry() -> ! {
    uart_puts("\nHello TRON (Rust)\n");

    // simple spinner
    loop {
        uart_putc(b.);
        // crude delay
        for _ in 0..80_000 { core::hint::spin_loop(); }
    }
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    uart_puts("\nPANIC\n");
    loop { core::hint::spin_loop(); }
}
