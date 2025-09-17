fn main() {
    // AArch64 用のクロスコンパイラを明示
    let mut b = cc::Build::new();
    b.compiler("aarch64-linux-gnu-gcc")
        .file("boot/start.S")
        .flag("-nostdlib")
        .flag("-march=armv8-a")      // 任意（QEMU virt想定）
        .flag("-Wno-unused-parameter");
    b.compile("start");

    println!("cargo:rerun-if-changed=boot/start.S");
    println!("cargo:rerun-if-changed=boot/linker.ld");
}
