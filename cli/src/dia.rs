use std::{
    path::{Path, PathBuf},
    process::Command,
    thread,
    time::{Duration, Instant},
};

use anyhow::{bail, Context, Result};
use serde::Deserialize;

use crate::{
    child::{self, Finished, OnInterrupt},
    env::Env,
    signals::{self, Cancelled},
    ui::Spinner,
};

pub struct Diapatch(PathBuf);

#[derive(Deserialize)]
pub struct Status {
    pub official: Option<String>,
    pub installed: Option<String>,
    pub patched: bool,
    pub staged: Option<String>,
    pub feed: Option<String>,
    pub channel: String,
}

impl Diapatch {
    pub fn find(env: &Env) -> Result<Self> {
        let path = env.diapatch();
        if !path.is_file() {
            bail!(
                "DiaTweaks isn't installed: {} is missing. Run install.sh first.",
                path.display()
            );
        }
        Ok(Self(path))
    }

    pub fn run(
        &self,
        args: &[&str],
        on_interrupt: OnInterrupt,
        spinner: &Spinner,
    ) -> Result<Finished> {
        child::run(Command::new(&self.0).args(args), on_interrupt, spinner)
    }

    pub fn status(&self, spinner: &Spinner) -> Result<Status> {
        let done = self.run(&["status", "--json"], OnInterrupt::StopDownloads, spinner)?;
        if signals::interrupted() {
            bail!(Cancelled::nothing_changed());
        }
        let json = done.output.lines().rev().find(|line| line.starts_with('{'));
        match (done.status.success(), json) {
            (true, Some(json)) => serde_json::from_str(json)
                .context("diapatch status gave an answer diatweaks can't read"),
            _ => bail!("diapatch status failed:\n{}", done.tail(5)),
        }
    }
}

pub fn is_newer(version: &str, than: &str) -> bool {
    numbers(build(version)) > numbers(build(than))
}

fn build(version: &str) -> &str {
    version
        .rsplit_once(" (")
        .and_then(|(_, build)| build.strip_suffix(')'))
        .unwrap_or(version)
}

fn numbers(text: &str) -> Vec<u64> {
    text.split(|c: char| !c.is_ascii_digit())
        .filter_map(|part| part.parse().ok())
        .collect()
}

fn dictionary(path: PathBuf) -> Option<plist::Dictionary> {
    plist::Value::from_file(path).ok()?.into_dictionary()
}

pub fn version_of(app: &Path) -> Option<String> {
    let info = dictionary(app.join("Contents/Info.plist"))?;
    let short = info.get("CFBundleShortVersionString")?.as_string()?;
    let build = info.get("CFBundleVersion")?.as_string()?;
    Some(format!("{short} ({build})"))
}

pub fn is_patched(app: &Path) -> bool {
    dictionary(app.join("Contents/Info.plist"))
        .and_then(|info| info.get("DiaPatches")?.as_boolean())
        .unwrap_or(false)
}

pub fn safe_mode(support: &Path) -> i64 {
    dictionary(support.join("safe-mode.plist"))
        .and_then(|state| state.get("level")?.as_signed_integer())
        .unwrap_or(0)
}

pub fn safe_mode_parked(support: &Path) -> bool {
    dictionary(support.join("safe-mode.plist"))
        .and_then(|state| state.get("steppedDown")?.as_boolean())
        .unwrap_or(false)
}

fn processes(app: &Path) -> Vec<(libc::pid_t, PathBuf)> {
    let Ok(root) = app.canonicalize() else {
        return Vec::new();
    };
    child::all_pids()
        .into_iter()
        .filter_map(|pid| child::pid_path(pid).map(|path| (pid, path)))
        .filter(|(_, path)| path.starts_with(&root))
        .collect()
}

pub fn is_running(app: &Path) -> bool {
    !processes(app).is_empty()
}

/// By process ID, as ⌘Q would: SIGTERM looks like a crash to safe mode, and another Dia may be open.
pub fn quit(app: &Path) -> Result<()> {
    let macos = app.canonicalize()?.join("Contents/MacOS");
    for (pid, path) in processes(app) {
        if path.parent() != Some(macos.as_path()) {
            continue;
        }
        let script = format!(
            "ObjC.import('AppKit'); $.NSRunningApplication.runningApplicationWithProcessIdentifier({pid}).terminate"
        );
        child::quick(Command::new("/usr/bin/osascript").args(["-l", "JavaScript", "-e", &script]));
    }
    let deadline = Instant::now() + Duration::from_secs(60);
    while is_running(app) {
        if Instant::now() > deadline {
            bail!(
                "Dia didn't quit. If it's showing a dialog, answer it, quit Dia, then try again."
            );
        }
        thread::sleep(Duration::from_millis(250));
    }
    Ok(())
}
