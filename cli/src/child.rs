use std::{
    ffi::OsStr,
    io::{Read, Seek, SeekFrom},
    mem,
    os::unix::{ffi::OsStrExt, process::CommandExt},
    path::{Path, PathBuf},
    process::{Command, ExitStatus, Stdio},
    thread,
    time::{Duration, Instant},
};

use anyhow::{bail, Context, Result};

use crate::{
    signals::{self, Cancelled},
    ui::Spinner,
};

pub enum OnInterrupt {
    Stop,
    /// Only downloads stop: diapatch moves whole app bundles, which must finish.
    StopDownloads,
    Finish(&'static str),
}

pub struct Finished {
    pub status: ExitStatus,
    pub output: String,
}

impl Finished {
    pub fn tail(&self, count: usize) -> String {
        let lines: Vec<&str> = self
            .output
            .lines()
            .filter(|line| !line.trim().is_empty())
            .collect();
        if lines.is_empty() {
            return format!("It stopped with {} and printed nothing.", self.status);
        }
        lines[lines.len().saturating_sub(count)..].join("\n")
    }
}

/// An unlinked file, not a pipe: the child must not die of SIGPIPE if diatweaks is killed.
pub fn run(
    command: &mut Command,
    on_interrupt: OnInterrupt,
    spinner: &Spinner,
) -> Result<Finished> {
    let program = Path::new(command.get_program()).display().to_string();
    let mut log = tempfile::tempfile().context("Couldn't create a temporary file")?;
    let mut child = command
        .process_group(0)
        .stdin(Stdio::null())
        .stdout(log.try_clone()?)
        .stderr(log.try_clone()?)
        .spawn()
        .with_context(|| format!("Couldn't run {program}"))?;
    let pid = child.id() as libc::pid_t;
    let mut stopping_since = None;
    let status = loop {
        if let Some(status) = child.try_wait()? {
            break status;
        }
        if signals::interrupted() {
            match on_interrupt {
                OnInterrupt::Stop => match stopping_since {
                    None => {
                        spinner.set_message("Stopping…");
                        unsafe { libc::killpg(pid, libc::SIGINT) };
                        stopping_since = Some(Instant::now());
                    }
                    Some(since) if since.elapsed() > Duration::from_secs(10) => unsafe {
                        libc::killpg(pid, libc::SIGKILL);
                    },
                    Some(_) => {}
                },
                OnInterrupt::StopDownloads => {
                    if stopping_since.is_none() {
                        spinner.set_message("Stopping after the current step…");
                        stopping_since = Some(Instant::now());
                    }
                    stop_downloads(pid);
                }
                OnInterrupt::Finish(why) => {
                    if stopping_since.is_none() {
                        spinner.set_message(why);
                        stopping_since = Some(Instant::now());
                    }
                }
            }
        }
        thread::sleep(Duration::from_millis(50));
    };
    if matches!(on_interrupt, OnInterrupt::Stop) && signals::interrupted() {
        bail!(Cancelled::nothing_changed());
    }
    let mut bytes = Vec::new();
    log.seek(SeekFrom::Start(0))?;
    log.read_to_end(&mut bytes)?;
    Ok(Finished {
        status,
        output: String::from_utf8_lossy(&bytes).into_owned(),
    })
}

fn stop_downloads(parent: libc::pid_t) {
    let curl = Path::new("/usr/bin/curl");
    for pid in child_pids(parent) {
        if pid_path(pid).is_some_and(|path| path == curl) {
            unsafe { libc::kill(pid, libc::SIGTERM) };
        }
    }
}

fn child_pids(parent: libc::pid_t) -> Vec<libc::pid_t> {
    let mut pids: Vec<libc::pid_t> = vec![0; 256];
    let size = (pids.len() * mem::size_of::<libc::pid_t>()) as libc::c_int;
    let count = unsafe { libc::proc_listchildpids(parent, pids.as_mut_ptr().cast(), size) };
    pids.truncate(count.max(0) as usize);
    pids
}

pub fn all_pids() -> Vec<libc::pid_t> {
    let capacity = unsafe { libc::proc_listallpids(std::ptr::null_mut(), 0) }.max(0) as usize + 64;
    let mut pids: Vec<libc::pid_t> = vec![0; capacity];
    let size = (pids.len() * mem::size_of::<libc::pid_t>()) as libc::c_int;
    let count = unsafe { libc::proc_listallpids(pids.as_mut_ptr().cast(), size) };
    pids.truncate(count.max(0) as usize);
    pids
}

pub fn pid_path(pid: libc::pid_t) -> Option<PathBuf> {
    let mut buffer = [0u8; libc::PROC_PIDPATHINFO_MAXSIZE as usize];
    let length =
        unsafe { libc::proc_pidpath(pid, buffer.as_mut_ptr().cast(), buffer.len() as u32) };
    (length > 0).then(|| PathBuf::from(OsStr::from_bytes(&buffer[..length as usize])))
}

pub fn quick(command: &mut Command) -> Option<String> {
    let output = command
        .process_group(0)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).trim().to_string())
}
