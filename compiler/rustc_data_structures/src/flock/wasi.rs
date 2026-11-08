//! WASI preview 1 has no advisory file locking. A rustc running on WASI is one
//! single-threaded wasm instance, and hosts that run several instances (e.g. a browser
//! playground) give each its own filesystem or run them one after another, so there is
//! nobody to exclude: opening (and optionally creating) the lock file is enough.
//!
//! The lock file still has to exist, because incremental compilation's session-directory
//! garbage collection looks for it. Two rustc instances sharing one incremental directory
//! concurrently are NOT protected against each other.

use std::fs::{File, OpenOptions};
use std::io;
use std::path::Path;

#[derive(Debug)]
pub struct Lock {
    _file: File,
}

impl Lock {
    pub fn new(p: &Path, _wait: bool, create: bool, _exclusive: bool) -> io::Result<Lock> {
        let file = OpenOptions::new().read(true).write(true).create(create).open(p)?;
        Ok(Lock { _file: file })
    }

    pub fn error_unsupported(_err: &io::Error) -> bool {
        false
    }
}
