use std::{
    error::Error,
    fmt, io,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, LazyLock,
    },
};

use signal_hook::consts::{SIGHUP, SIGINT, SIGTERM};

static INTERRUPTED: LazyLock<Arc<AtomicBool>> = LazyLock::new(Arc::default);

pub fn install() -> io::Result<()> {
    for signal in [SIGINT, SIGTERM, SIGHUP] {
        signal_hook::flag::register(signal, Arc::clone(&INTERRUPTED))?;
    }
    Ok(())
}

pub fn interrupted() -> bool {
    INTERRUPTED.load(Ordering::SeqCst)
}

#[derive(Debug)]
pub struct Cancelled(pub String);

impl Cancelled {
    pub fn nothing_changed() -> Self {
        Self("Cancelled. Nothing changed.".into())
    }
}

impl fmt::Display for Cancelled {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl Error for Cancelled {}
