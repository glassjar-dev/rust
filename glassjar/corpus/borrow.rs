// Does not compile: these get past the type checker and must be caught by the borrow checker.
fn main() {
    let s = String::from("moved");
    let t = s;
    println!("{s} {t}");
    let mut v = vec![1, 2, 3];
    let first = &v[0];
    v.push(4);
    println!("{first}");
}
