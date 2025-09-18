#![no_std]
#![no_main]
mod arch;

use core::panic::PanicInfo;
use core::sync::atomic::{AtomicUsize, Ordering};

// ===== UART =====
const UART0_BASE: usize = 0x0900_0000;
const DR: usize = UART0_BASE + 0x00;
const FR: usize = UART0_BASE + 0x18;
const TXFF: u32 = 1 << 5;

#[inline(always)]
fn mmio_write(addr: usize, val: u32) { unsafe { core::ptr::write_volatile(addr as *mut u32, val) } }
#[inline(always)]
fn mmio_read(addr: usize) -> u32 { unsafe { core::ptr::read_volatile(addr as *const u32) } }
fn uart_putc(c: u8) { while (mmio_read(FR) & TXFF) != 0 {} mmio_write(DR, c as u32); }
fn uart_puts(s: &str){ for b in s.bytes(){ if b==b'\n'{uart_putc(b'\r');} uart_putc(b);} }
fn uart_hex(mut v:u32){
    for i in (0..8).rev() {
        let d = ((v >> (i*4)) & 0xF) as u8;
        uart_putc(if d < 10 { b'0'+d } else { b'A'+(d-10) });
    }
}

// ===== タスク =====
type Task = fn();
fn task_a(){ uart_putc(b'A'); }
fn task_b(){ uart_putc(b'B'); }
static CURRENT: AtomicUsize = AtomicUsize::new(0);
static TASKS: [Task; 2] = [task_a, task_b];

// TRON最小ダミー
#[allow(non_camel_case_types)] type ID=i32; #[allow(non_camel_case_types)] type ER=i32; #[allow(non_camel_case_types)] type INT=i32; #[allow(non_camel_case_types)] type TMO=i32;
#[repr(C)] pub struct T_CTSK{ pub task: fn(*mut()), pub stksz:u32, pub itskpri:u32, pub exinf:*mut() }
#[no_mangle] pub extern "C" fn tk_cre_tsk(_p:*const T_CTSK)->ID{1}
#[no_mangle] pub extern "C" fn tk_sta_tsk(_id:ID,_st:INT)->ER{0}
#[no_mangle] pub extern "C" fn tk_slp_tsk(_t:TMO)->ER{0}

// IRQエントリ
#[no_mangle]
pub extern "C" fn irq_entry_rust() {
    // どのIRQか可視化
    let intid = arch::irq_ack_eoi();
    // 100msごとに現在タスクを切替（1ms tickなら t%100==0）
    let t = arch::ticks();
    if t % 100 == 0 {
        let next = (CURRENT.load(Ordering::Relaxed) + 1) % TASKS.len();
        CURRENT.store(next, Ordering::Relaxed);
        // デバッグ：切替時に [irq=XXXX] を一度だけ出す
        uart_puts("[irq=");
        uart_hex(intid);
        uart_puts("]");
    }
}

#[no_mangle]
pub extern "C" fn rust_entry() -> ! {
    uart_puts("\nHello TRON (Rust) + 1ms IRQ\n");

    // （任意）現在ELを吐く: 0x4=EL1, 0x8=EL2
    let mut el:u64=0; unsafe{ core::arch::asm!("mrs {0}, CurrentEL", out(reg) el); }
    uart_puts("EL="); uart_hex((el as u32)); uart_putc(b'\n');

    arch::gic_init();
    arch::timer_start_1ms();
    arch::irq_enable();

    loop {
        (TASKS[ CURRENT.load(Ordering::Relaxed) ])();
        for _ in 0..40_000 { core::hint::spin_loop(); }
    }
}

#[panic_handler]
fn panic(_: &PanicInfo) -> ! { uart_puts("\nPANIC\n"); loop{ core::hint::spin_loop(); } }
