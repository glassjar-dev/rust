// Reads lines from stdin, like an intro-course exercise.
use std::io::{self, BufRead, Write};
fn main() {
    let stdin = io::stdin();
    let mut total = 0i64;
    let mut lines = 0;
    for line in stdin.lock().lines() {
        let line = line.unwrap();
        lines += 1;
        for tok in line.split_whitespace() {
            match tok.parse::<i64>() { Ok(n) => total += n, Err(_) => eprintln!("skip {tok:?}") }
        }
    }
    let mut out = io::stdout().lock();
    writeln!(out, "{lines} lines, total {total}").unwrap();
}
