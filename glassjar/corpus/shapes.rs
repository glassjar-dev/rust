// Traits, generics, trait objects, operator overloading, Display.
use std::fmt;
use std::ops::Add;

trait Shape {
    fn area(&self) -> f64;
    fn name(&self) -> String { String::from("shape") }
}

struct Circle(f64);
struct Rect { w: f64, h: f64 }

impl Shape for Circle {
    fn area(&self) -> f64 { std::f64::consts::PI * self.0 * self.0 }
    fn name(&self) -> String { "circle".into() }
}
impl Shape for Rect {
    fn area(&self) -> f64 { self.w * self.h }
}

#[derive(Debug, Clone, Copy, PartialEq, PartialOrd, Default)]
struct Vec2 { x: f64, y: f64 }
impl Add for Vec2 {
    type Output = Vec2;
    fn add(self, o: Vec2) -> Vec2 { Vec2 { x: self.x + o.x, y: self.y + o.y } }
}
impl fmt::Display for Vec2 {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { write!(f, "({:.1}, {:.1})", self.x, self.y) }
}

fn largest<T: PartialOrd + Copy>(xs: &[T]) -> T {
    let mut best = xs[0];
    for &x in xs { if x > best { best = x; } }
    best
}

fn main() {
    let shapes: Vec<Box<dyn Shape>> = vec![Box::new(Circle(1.5)), Box::new(Rect { w: 2.0, h: 3.5 })];
    for s in &shapes { println!("{:>8}: {:8.3}", s.name(), s.area()); }
    let total: f64 = shapes.iter().map(|s| s.area()).sum();
    println!("total {total:.4}");
    let v = Vec2 { x: 1.0, y: 2.0 } + Vec2::default() + Vec2 { x: 0.5, y: -4.0 };
    println!("{v} {v:?} {}", largest(&[3, 9, 2]));
    println!("{:?} {:#x} {:08.3} {:e} {:+}", largest(&[1.5, 0.2]), 255, 3.14159, 1234.5, 7);
}
