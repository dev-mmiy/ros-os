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
