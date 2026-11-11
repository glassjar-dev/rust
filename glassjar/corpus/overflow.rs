// Arithmetic overflow is checked in the default profile; exit code via process::exit.
fn fact(n: u32) -> u32 { if n == 0 { 1 } else { n * fact(n - 1) } }
fn main() {
    println!("{}", fact(10));
    println!("{:?} {:?}", 200u8.checked_add(100), 200u8.wrapping_add(100));
    let r = std::panic::catch_unwind(|| 1);
    println!("{r:?} {}", i128::MAX / 3);
    println!("{:.3} {}", (2.0f64).sqrt().sin().powi(3), f32::MAX as f64 / 7.0);
    std::process::exit(3);
}
