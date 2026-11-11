// Enums, pattern matching, Result and ?, custom errors, Option combinators.
use std::collections::BTreeMap;
use std::fmt;

#[derive(Debug)]
enum BankError { NoAccount(String), Insufficient { need: u64, have: u64 }, Parse(std::num::ParseIntError) }
impl fmt::Display for BankError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            BankError::NoAccount(n) => write!(f, "no account named {n}"),
            BankError::Insufficient { need, have } => write!(f, "need {need} but have {have}"),
            BankError::Parse(e) => write!(f, "bad amount: {e}"),
        }
    }
}
impl std::error::Error for BankError {}
impl From<std::num::ParseIntError> for BankError { fn from(e: std::num::ParseIntError) -> Self { BankError::Parse(e) } }

#[derive(Default)]
struct Bank { accounts: BTreeMap<String, u64> }
impl Bank {
    fn apply(&mut self, line: &str) -> Result<u64, BankError> {
        let parts: Vec<&str> = line.split_whitespace().collect();
        match parts.as_slice() {
            ["deposit", name, amount] => {
                let balance = self.accounts.entry(name.to_string()).or_insert(0);
                *balance += amount.parse::<u64>()?;
                Ok(*balance)
            }
            ["withdraw", name, amount] => {
                let need: u64 = amount.parse()?;
                let have = self.accounts.get_mut(*name).ok_or_else(|| BankError::NoAccount(name.to_string()))?;
                if *have < need { return Err(BankError::Insufficient { need, have: *have }); }
                *have -= need;
                Ok(*have)
            }
            _ => Ok(self.accounts.values().sum()),
        }
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut bank = Bank::default();
    for line in ["deposit ada 100", "withdraw ada 30", "withdraw bob 5", "withdraw ada 500", "deposit ada x1", "total"] {
        match bank.apply(line) {
            Ok(balance) => println!("{line:<18} -> {balance}"),
            Err(e) => println!("{line:<18} !! {e}"),
        }
    }
    let first = bank.accounts.iter().next().map(|(k, v)| format!("{k}={v}")).unwrap_or_default();
    println!("{first}");
    let n: i32 = "42".parse()?;
    println!("{}", n.checked_mul(2).and_then(|x| x.checked_add(1)).unwrap_or(-1));
    Ok(())
}
