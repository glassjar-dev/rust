// Ownership: Box, Rc<RefCell>, lifetimes, Drop, iterators implemented by hand.
use std::cell::RefCell;
use std::rc::Rc;

#[derive(Debug)]
enum List { Cons(i32, Box<List>), Nil }
use List::{Cons, Nil};
impl List {
    fn sum(&self) -> i32 { match self { Cons(v, rest) => v + rest.sum(), Nil => 0 } }
}

struct Node { val: u32, children: Vec<Rc<RefCell<Node>>> }
impl Drop for Node { fn drop(&mut self) { println!("drop node {}", self.val); } }

fn longest<'a>(a: &'a str, b: &'a str) -> &'a str { if a.len() >= b.len() { a } else { b } }

struct Fib { a: u64, b: u64 }
impl Iterator for Fib {
    type Item = u64;
    fn next(&mut self) -> Option<u64> { let r = self.a; self.a = self.b; self.b += r; Some(r) }
}

fn main() {
    let list = Cons(1, Box::new(Cons(2, Box::new(Cons(3, Box::new(Nil))))));
    println!("{:?} sums to {}", list, list.sum());
    let leaf = Rc::new(RefCell::new(Node { val: 3, children: vec![] }));
    let root = Rc::new(RefCell::new(Node { val: 1, children: vec![leaf.clone()] }));
    leaf.borrow_mut().val += 10;
    println!("root {} child {} rc {}", root.borrow().val, root.borrow().children[0].borrow().val, Rc::strong_count(&leaf));
    drop(root);
    let s1 = String::from("ownership");
    let res;
    { let s2 = String::from("borrow"); res = longest(&s1, &s2).to_uppercase(); }
    println!("{res}");
    let evens: Vec<u64> = Fib { a: 0, b: 1 }.filter(|x| x % 2 == 0).take_while(|&x| x < 5000).collect();
    println!("{evens:?}");
    let mut words: Vec<String> = "the quick brown fox jumps over the lazy dog".split(' ').map(String::from).collect();
    words.sort_by(|a, b| b.len().cmp(&a.len()).then(a.cmp(b)));
    words.dedup();
    println!("{}", words.join(","));
    let text: String = words.iter().flat_map(|w| w.chars().rev()).filter(|c| !"aeiou".contains(*c)).collect();
    println!("{text} {}", text.chars().count());
}
