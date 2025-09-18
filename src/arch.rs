#![allow(dead_code)]
use core::arch::asm;

// ===== Generic Timer =====
// * 物理(CNTP)が環境で届かないケースを避けるため、仮想(CNTV)を既定にする
#[inline(always)]
fn cntfrq() -> u64 { let v:u64; unsafe{ asm!("mrs {0}, CNTFRQ_EL0", out(reg)v) }; v }
#[inline(always)]
fn cntvct() -> u64 { let v:u64; unsafe{ asm!("mrs {0}, CNTVCT_EL0", out(reg)v) }; v }
#[inline(always)]
fn set_v_cval(v: u64) { unsafe{ asm!("msr CNTV_CVAL_EL0, {0}", in(reg) v) } }
#[inline(always)]
fn set_v_ctl(v: u32)  { unsafe{
    let v64: u64 = v as u64;
    asm!("msr CNTV_CTL_EL0, {0}", in(reg) v64)
}}

// ===== GICv2 (QEMU virt,gic-version=2) =====
const GICD_BASE: usize = 0x0800_0000;
const GICC_BASE: usize = 0x0801_0000;
// Distributor
const GICD_CTLR: usize       = GICD_BASE + 0x000;
const GICD_ISENABLER0: usize = GICD_BASE + 0x100;
const GICD_IPRIORITYR0: usize= GICD_BASE + 0x400;

const GICD_IGROUPR0: usize = GICD_BASE + 0x080;

// CPU IF
const GICC_CTLR: usize = GICC_BASE + 0x000;
const GICC_PMR:  usize = GICC_BASE + 0x004;
const GICC_IAR:  usize = GICC_BASE + 0x00C;
const GICC_EOIR: usize = GICC_BASE + 0x010;

#[inline(always)]
fn mmio_w(addr: usize, val: u32){ unsafe{ core::ptr::write_volatile(addr as *mut u32, val) } }
#[inline(always)]
fn mmio_r(addr: usize) -> u32 { unsafe{ core::ptr::read_volatile(addr as *const u32) } }

// PPI IDs（よく使うもの）
// 27: CNTVIRQ (Virtual timer), 30: CNTPNSIRQ (Non-secure physical) の実装が多い
const INTR_CNTV: u32 = 27;

pub fn gic_init() {
    // ===== GIC Distributor =====
    // 1) PPI27..31 を Group1 (= Non-secure) に割り当てる
    const GICD_IGROUPR0: usize = GICD_BASE + 0x080; // group設定 (ID 0..31)
    let mask_27_31 = (1u32<<27) | (1u32<<28) | (1u32<<29) | (1u32<<30) | (1u32<<31);
    // 既存値に OR（他のIDに影響しない）
    mmio_w(GICD_IGROUPR0, mmio_r(GICD_IGROUPR0) | mask_27_31);

    // 2) 優先度を 0（最優先）に
    for i in 0..8 { mmio_w(GICD_IPRIORITYR0 + i*4, 0x0000_0000); }

    // 3) PPI27..31 を有効化
    mmio_w(GICD_ISENABLER0, mask_27_31);

    // 4) Distributor: Group0 + Group1 を有効化（bit0=Grp0, bit1=Grp1）
    mmio_w(GICD_CTLR, 0b11);

    // ===== GIC CPU Interface =====
    // PMR: 0xFF（広めに通す）
    mmio_w(GICC_PMR, 0xFF);
    // CPU IF: Group0 + Group1 を有効化（bit0=Grp0, bit1=Grp1）
    mmio_w(GICC_CTLR, 0b11);
}

pub fn timer_start_1ms() {
    let f = cntfrq();
    set_v_cval(cntvct() + f/1000); // 1ms 先
    set_v_ctl(1);                  // enable=1, imask=0
}

static mut TICKS: u64 = 0;
pub fn ticks() -> u64 { unsafe { TICKS } }

// 呼ばれるたびにEOIする。どのIRQかを返してデバッグ可視化
pub fn irq_ack_eoi() -> u32 {
    let iar = mmio_r(GICC_IAR);
    let intid = (iar & 0x3FF) as u32;

    // 仮想タイマなら次回セット＋tick++
    if intid == INTR_CNTV {
        let f = cntfrq();
        set_v_cval(cntvct() + f/1000);
        unsafe { TICKS = TICKS.wrapping_add(1); }
    }

    mmio_w(GICC_EOIR, iar);
    intid
}

pub fn irq_enable() {
    unsafe {
        core::arch::asm!("msr DAIFClr, #2", options(nomem, nostack));
    }
}
