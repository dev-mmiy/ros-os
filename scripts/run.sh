\
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
