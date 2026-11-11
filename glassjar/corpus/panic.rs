// A panic must print the message and exit non-zero.
fn pick(xs: &[i32], i: usize) -> i32 { xs[i] }
fn main() {
    let xs = vec![1, 2, 3];
    println!("{}", pick(&xs, 1));
    let i = xs.len() + 2;
    println!("{}", pick(&xs, i));
}
