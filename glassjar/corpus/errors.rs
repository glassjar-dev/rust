// Does not compile: the borrow checker and type checker must report these.
fn main() {
    let s = String::from("moved");
    let t = s;
    println!("{s} {t}");
    let x: i32 = "five";
    let mut v = vec![1, 2, 3];
    let first = &v[0];
    v.push(4);
    println!("{first}");
}
