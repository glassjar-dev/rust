use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};
use std::fmt;

#[derive(Debug, Clone, PartialEq)]
enum Token { Num(f64), Op(char), LParen, RParen }

fn tokenize(s: &str) -> Vec<Token> {
    let mut out = Vec::new();
    let cs: Vec<char> = s.chars().collect();
    let mut i = 0;
    while i < cs.len() {
        let c = cs[i];
        if c.is_ascii_digit() || c == '.' {
            let st = i;
            while i < cs.len() && (cs[i].is_ascii_digit() || cs[i] == '.') { i += 1; }
            out.push(Token::Num(cs[st..i].iter().collect::<String>().parse().unwrap()));
            continue;
        }
        match c { '+' | '-' | '*' | '/' => out.push(Token::Op(c)), '(' => out.push(Token::LParen), ')' => out.push(Token::RParen), _ => {} }
        i += 1;
    }
    out
}

fn prec(op: char) -> u8 { if op == '+' || op == '-' { 1 } else { 2 } }

fn eval(tokens: &[Token]) -> f64 {
    let mut nums: Vec<f64> = vec![];
    let mut ops: Vec<Token> = vec![];
    fn apply(nums: &mut Vec<f64>, op: char) {
        let b = nums.pop().unwrap(); let a = nums.pop().unwrap();
        nums.push(match op { '+' => a + b, '-' => a - b, '*' => a * b, _ => a / b });
    }
    for t in tokens {
        match t {
            Token::Num(n) => nums.push(*n),
            Token::LParen => ops.push(t.clone()),
            Token::RParen => { while let Some(Token::Op(o)) = ops.last().cloned() { apply(&mut nums, o); ops.pop(); } ops.pop(); }
            Token::Op(o) => {
                while let Some(Token::Op(p)) = ops.last().cloned() { if prec(p) >= prec(*o) { apply(&mut nums, p); ops.pop(); } else { break; } }
                ops.push(t.clone());
            }
        }
    }
    while let Some(Token::Op(o)) = ops.pop() { apply(&mut nums, o); }
    nums[0]
}

trait Shape { fn area(&self) -> f64; fn name(&self) -> String; }
struct Circle(f64);
struct Rect { w: f64, h: f64 }
impl Shape for Circle { fn area(&self) -> f64 { 3.14159 * self.0 * self.0 } fn name(&self) -> String { "circle".into() } }
impl Shape for Rect { fn area(&self) -> f64 { self.w * self.h } fn name(&self) -> String { format!("rect {}x{}", self.w, self.h) } }

struct Matrix { r: usize, c: usize, d: Vec<i64> }
impl Matrix {
    fn ident(n: usize) -> Self { let mut d = vec![0; n * n]; for i in 0..n { d[i * n + i] = 1; } Matrix { r: n, c: n, d } }
    fn mul(&self, o: &Matrix) -> Matrix {
        let mut d = vec![0; self.r * o.c];
        for i in 0..self.r { for j in 0..o.c { for k in 0..self.c { d[i * o.c + j] += self.d[i * self.c + k] * o.d[k * o.c + j]; } } }
        Matrix { r: self.r, c: o.c, d }
    }
}
impl fmt::Display for Matrix {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        for i in 0..self.r { let row: Vec<String> = (0..self.c).map(|j| self.d[i * self.c + j].to_string()).collect(); writeln!(f, "[{}]", row.join(", "))?; }
        Ok(())
    }
}

fn bfs(adj: &HashMap<u32, Vec<u32>>, s: u32) -> BTreeMap<u32, u32> {
    let mut dist = BTreeMap::new(); let mut q = VecDeque::new();
    dist.insert(s, 0); q.push_back(s);
    while let Some(u) = q.pop_front() {
        let du = dist[&u];
        for &v in adj.get(&u).map(|v| v.as_slice()).unwrap_or(&[]) { if !dist.contains_key(&v) { dist.insert(v, du + 1); q.push_back(v); } }
    }
    dist
}

fn generic_max<T: PartialOrd + Copy>(xs: &[T]) -> Option<T> { xs.iter().copied().fold(None, |m, x| match m { None => Some(x), Some(y) => Some(if x > y { x } else { y }) }) }

fn main() {
    println!("{}", eval(&tokenize("3 + 4 * (2 - 1) / 2")));
    let shapes: Vec<Box<dyn Shape>> = vec![Box::new(Circle(1.5)), Box::new(Rect { w: 2.0, h: 3.0 })];
    for s in &shapes { println!("{} {:.2}", s.name(), s.area()); }
    let mut m = Matrix { r: 2, c: 2, d: vec![1, 1, 1, 0] }; let mut acc = Matrix::ident(2);
    for _ in 0..10 { acc = acc.mul(&m); } m = acc; print!("{}", m);
    let mut adj: HashMap<u32, Vec<u32>> = HashMap::new();
    for (a, b) in [(1, 2), (1, 3), (2, 4), (3, 4), (4, 5)] { adj.entry(a).or_default().push(b); adj.entry(b).or_default().push(a); }
    println!("{:?}", bfs(&adj, 1));
    let words = "the quick brown fox jumps over the lazy dog the end";
    let mut freq: HashMap<&str, usize> = HashMap::new(); for w in words.split_whitespace() { *freq.entry(w).or_insert(0) += 1; }
    let mut fv: Vec<_> = freq.into_iter().collect(); fv.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    println!("{:?}", &fv[..3]);
    let uniq: HashSet<char> = words.chars().filter(|c| c.is_alphabetic()).collect(); println!("{}", uniq.len());
    println!("{:?} {:?}", generic_max(&[3, 9, 2]), generic_max(&[1.5, -2.0]));
    let s: String = (1..=20).filter(|x| x % 3 == 0).map(|x| x.to_string()).collect::<Vec<_>>().join(",");
    println!("{s}");
}
