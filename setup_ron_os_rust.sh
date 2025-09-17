#!/usr/bin/env bash
# setup_ron_os_rust.sh
# Create a minimal Rust bare-metal PoC for QEMU aarch64 (virt + PL011)
# Usage: ./setup_ron_os_rust.sh [project_dir] [--force]
set -euo pipefail

PROJECT_DIR="${1:-ron-os-rust}"
FORCE=0
if [[ "${*:-}" == *"--force"* ]]; then FORCE=1; fi

say() { echo -e "\033[1;32m[setup]\033[0m $*"; }
skip(){ echo -e "\033[1;34m[skip]\033[0m $*"; }

write_file() {
  local path="$1"; shift; local content="$*"
  if [[ -e "$path" && $FORCE -eq 0 ]]; then skip "$path exists; use --force to overwrite"; return 0; fi
  mkdir -p "$(dirname "$path")"; printf "%s" "$content" > "$path"; say "wrote $path"
}

say "Create Rust PoC at: $PROJECT_DIR"
mkdir -p "$PROJECT_DIR"/{boot,scripts,.cargo,docs,src}

# --- Cargo.toml ---
write_file "$PROJECT_DIR/Cargo.toml" '\
[package]
name = "ron"
version = "0.1.0"
edition = "2021"

[dependencies]

[build-dependencies]
cc = "1"
'

# --- .cargo/config.toml ---
write_file "$PROJECT_DIR/.cargo/config.toml" '\
[build]
target = "aarch64-unknown-none"

[target.aarch64-unknown-none]
rustflags = [
  "-C", "link-arg=-Tboot/linker.ld",
  "-C", "relocation-model=static",
  "-C", "panic=abort",
]
# use LLD (default for many bare-metal targets)
linker-flavor = "ld.lld"
'

# --- boot/linker.ld ---
write_file "$PROJECT_DIR/boot/linker.ld" '\
ENTRY(_start)
SECTIONS {
  . = 0x40080000;          /* QEMU virt DDR region */
  .text : { *(.text*) }
  .rodata : { *(.rodata*) }
  .data : { *(.data*) }
  .bss  : { *(.bss*) *(COMMON) }
}
'

# --- boot/start.S (EL1, set stack, jump to Rust entry) ---
write_file "$PROJECT_DIR/boot/start.S" '\
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
'

# --- build.rs (compile start.S) ---
write_file "$PROJECT_DIR/build.rs" '\
fn main() {
    cc::Build::new()
        .file("boot/start.S")
        .flag("-nostdlib")
        .compile("start");
    println!("cargo:rerun-if-changed=boot/start.S");
    println!("cargo:rerun-if-changed=boot/linker.ld");
}
'

# --- src/main.rs (no_std + UART Hello) ---
write_file "$PROJECT_DIR/src/main.rs" '\
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
        if b == b'\n' { uart_putc(b'\r'); }
        uart_putc(b);
    }
}

#[no_mangle]
pub extern "C" fn rust_entry() -> ! {
    uart_puts("\nHello TRON (Rust)\n");

    // simple spinner
    loop {
        uart_putc(b'.');
        // crude delay
        for _ in 0..80_000 { core::hint::spin_loop(); }
    }
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    uart_puts("\nPANIC\n");
    loop { core::hint::spin_loop(); }
}
'

# --- scripts/run.sh ---
write_file "$PROJECT_DIR/scripts/run.sh" '\
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# build
if ! command -v cargo >/dev/null; then
  echo "cargo not found. Install Rust (rustup) first."; exit 1
fi
rustup target add aarch64-unknown-none >/dev/null 2>&1 || true
cargo build --release
# run
KERNEL=target/aarch64-unknown-none/release/ron
exec qemu-system-aarch64 -machine virt -cpu cortex-a53 -nographic -kernel "$KERNEL"
'
chmod +x "$PROJECT_DIR/scripts/run.sh"

# --- docs/RUNBOOK.md ---
write_file "$PROJECT_DIR/docs/RUNBOOK.md" '\
# RUNBOOK (Rust Bare-metal PoC on QEMU aarch64)

## Prereqs (WSL/Ubuntu)
```bash
sudo apt-get update && sudo apt-get install -y qemu-system-arm
curl https://sh.rustup.rs -sSf | sh -s -- -y
source $HOME/.cargo/env
rustup target add aarch64-unknown-none
