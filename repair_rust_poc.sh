#!/usr/bin/env bash
set -euo pipefail

# 1) 最小構成ファイルを上書き（先頭に変な文字が残らないよう cat <<'EOF' を利用）
mkdir -p .cargo boot src scripts

cat > Cargo.toml <<'EOF'
[package]
name = "ron"
version = "0.1.0"
edition = "2021"

[dependencies]

[build-dependencies]
cc = "1"
EOF

cat > .cargo/config.toml <<'EOF'
[build]
target = "aarch64-unknown-none"

[target.aarch64-unknown-none]
rustflags = [
  "-C", "link-arg=-Tboot/linker.ld",
  "-C", "panic=abort",
]
# LLD を使う（GNU ld 不要）
linker = "rust-lld"
EOF

cat > boot/linker.ld <<'EOF'
ENTRY(_start)
SECTIONS {
  . = 0x40080000;          /* QEMU virt DDR region */
  .text : { *(.text*) }
  .rodata : { *(.rodata*) }
  .data : { *(.data*) }
  .bss  : { *(.bss*) *(COMMON) }
}
EOF

cat > boot/start.S <<'EOF'
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
EOF

cat > build.rs <<'EOF'
fn main() {
    cc::Build::new()
        .file("boot/start.S")
        .flag("-nostdlib")
        .compile("start");
    println!("cargo:rerun-if-changed=boot/start.S");
    println!("cargo:rerun-if-changed=boot/linker.ld");
}
EOF

cat > src/main.rs <<'EOF'
#![no_std]
#![no_main]

use core::panic::PanicInfo;

const UART0_BASE: usize = 0x0900_0000; // PL011 on QEMU virt
const DR: usize = UART0_BASE + 0x00;
const FR: usize = UART0_BASE + 0x18;
const TXFF: u32 = 1 << 5;

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
        if b == b'\n' { uart_putc(b'\r'); }
        uart_putc(b);
    }
}

#[no_mangle]
pub extern "C" fn rust_entry() -> ! {
    uart_puts("\nHello TRON (Rust)\n");
    loop {
        uart_putc(b'.');
        for _ in 0..80_000 { core::hint::spin_loop(); }
    }
}

#[panic_handler]
fn panic(_: &PanicInfo) -> ! {
    uart_puts("\nPANIC\n");
    loop { core::hint::spin_loop(); }
}
EOF

cat > scripts/run.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

rustup target add aarch64-unknown-none >/dev/null 2>&1 || true
cargo build --release

rustup component add llvm-tools-preview >/dev/null 2>&1 || true
if ! command -v rust-objcopy >/dev/null 2>&1; then
  cargo install cargo-binutils >/dev/null 2>&1
fi

# ELF → フラットBINへ変換
rust-objcopy --strip-all -O binary \
  target/aarch64-unknown-none/release/ron \
  target/ron.bin

# QEMUで実行（addr は linker.ld の 0x40080000 と一致）
exec qemu-system-aarch64 -machine virt -cpu cortex-a53 -nographic -bios none \
  -device loader,file=target/ron.bin,addr=0x40080000
EOF
chmod +x scripts/run.sh

# 2) ビルド & 実行（ビルドが通ることと、ELFが生成されることを確認）
cargo clean
cargo build --release

# 3) ELFの存在チェック
[ -f target/aarch64-unknown-none/release/ron ] || { echo "ELF が生成されていません"; exit 1; }

# 4) 実行（フラットBIN変換→QEMU起動）
./scripts/run.sh
