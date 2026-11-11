// CPU-bound: sieve + sort + collatz, typical intro-course workloads.
fn collatz(mut n: u64) -> u32 { let mut c = 0; while n != 1 { n = if n % 2 == 0 { n / 2 } else { 3 * n + 1 }; c += 1; } c }
fn main() {
    let n = 2_000_000usize;
    let mut sieve = vec![true; n + 1];
    let mut i = 2;
    while i * i <= n { if sieve[i] { let mut j = i * i; while j <= n { sieve[j] = false; j += i; } } i += 1; }
    let primes: Vec<usize> = (2..=n).filter(|&k| sieve[k]).collect();
    let mut v: Vec<u64> = (0..500_000u64).map(|x| x.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407) >> 20).collect();
    v.sort();
    let best = (1..200_000u64).max_by_key(|&k| collatz(k)).unwrap();
    println!("{} primes, median {}, longest collatz {}", primes.len(), v[v.len() / 2], best);
}
