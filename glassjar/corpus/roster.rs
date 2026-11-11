use std::collections::HashMap;

#[derive(Debug, Clone)]
struct Student { name: String, grade: u32 }

fn average(xs: &[u32]) -> f64 { xs.iter().sum::<u32>() as f64 / xs.len() as f64 }

fn main() {
    let mut roster: HashMap<String, Student> = HashMap::new();
    for (i, n) in ["ada", "grace", "linus"].iter().enumerate() {
        roster.insert(n.to_string(), Student { name: n.to_string(), grade: 80 + i as u32 * 5 });
    }
    let mut grades: Vec<u32> = roster.values().map(|s| s.grade).collect();
    grades.sort();
    println!("{:?} avg {:.2}", grades, average(&grades));
    // HashMap order is random per run; sort so two runs can be compared.
    let mut students: Vec<&Student> = roster.values().collect();
    students.sort_by_key(|s| s.grade);
    for s in students { println!("{s:?}"); }
}
