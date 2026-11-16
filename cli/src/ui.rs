use std::{
    cell::Cell,
    fmt::Display,
    io::{self, IsTerminal, Write},
};

use anyhow::{Error, Result};
use cliclack::{Theme, ThemeState};

use crate::signals::{self, Cancelled};

/// Output errors are ignored: a closed pipe must not abort a step halfway.
pub struct Ui {
    pub interactive: bool,
    pub yes: bool,
    framed: Cell<bool>,
    in_menu: Cell<bool>,
}

impl Ui {
    pub fn new(yes: bool) -> Self {
        Self {
            interactive: io::stdin().is_terminal() && io::stderr().is_terminal(),
            yes,
            framed: Cell::new(false),
            in_menu: Cell::new(false),
        }
    }

    pub fn intro(&self) {
        self.framed.set(true);
        cliclack::set_theme(Frame);
        let _ = cliclack::intro(console::style(" DiaTweaks ").reverse());
    }

    pub fn enter_menu(&self, in_menu: bool) {
        self.in_menu.set(in_menu);
    }

    pub fn info(&self, message: impl Display) {
        match self.framed.get() {
            true => drop(cliclack::log::info(message)),
            false => say(message),
        }
    }

    pub fn remark(&self, message: impl Display) {
        match self.framed.get() {
            true => drop(cliclack::log::remark(message)),
            false => say(message),
        }
    }

    pub fn success(&self, message: impl Display) {
        match self.framed.get() {
            true => drop(cliclack::log::success(message)),
            false => say(message),
        }
    }

    pub fn warn(&self, message: impl Display) {
        match self.framed.get() {
            true => drop(cliclack::log::warning(message)),
            false => complain(format_args!("warning: {message}")),
        }
    }

    pub fn error(&self, err: &Error) {
        match self.framed.get() {
            true => drop(cliclack::log::error(format!("{err:#}"))),
            false => complain(format_args!("diatweaks: {err:#}")),
        }
    }

    pub fn note(&self, title: impl Display, body: impl Display) {
        match self.framed.get() {
            true => drop(cliclack::note(title, body)),
            false => say(body),
        }
    }

    pub fn done(&self, message: impl Display) {
        match (self.framed.get(), self.in_menu.get()) {
            (true, true) => drop(cliclack::log::success(message)),
            (true, false) => drop(cliclack::outro(message)),
            (false, _) => say(message),
        }
    }

    pub fn cancelled(&self, cancelled: &Cancelled) {
        match self.framed.get() {
            true => drop(cliclack::outro_cancel(cancelled)),
            false => complain(cancelled),
        }
    }

    pub fn failed(&self, err: &Error) {
        match self.framed.get() {
            true => drop(cliclack::outro_cancel(format!("{err:#}"))),
            false => complain(format_args!("diatweaks: {err:#}")),
        }
    }

    pub fn spinner(&self, label: impl Display) -> Spinner {
        let label = label.to_string();
        let bar = self.framed.get().then(|| {
            let bar = cliclack::spinner();
            bar.start(&label);
            bar
        });
        Spinner { bar, label }
    }

    pub fn proceed(&self, question: impl Display) -> Result<bool> {
        if self.yes || !self.interactive {
            return Ok(true);
        }
        prompt(cliclack::confirm(question).initial_value(true).interact())
    }

    pub fn choose(&self, question: impl Display, default: bool) -> Result<bool> {
        if self.yes {
            return Ok(true);
        }
        if !self.interactive {
            return Ok(false);
        }
        prompt(
            cliclack::confirm(question)
                .initial_value(default)
                .interact(),
        )
    }
}

struct Frame;

impl Theme for Frame {
    fn format_footer_with_message(&self, state: &ThemeState, message: &str) -> String {
        let line = match state {
            ThemeState::Active => format!("└  {message}"),
            ThemeState::Cancel | ThemeState::Submit => "│".into(),
            ThemeState::Error(err) => format!("└  {err}"),
        };
        format!("{}\n", self.bar_color(state).apply_to(line))
    }
}

pub fn prompt<T>(result: io::Result<T>) -> Result<T> {
    let cancelled = match &result {
        Ok(_) => false,
        Err(err) => matches!(
            err.kind(),
            io::ErrorKind::Interrupted | io::ErrorKind::UnexpectedEof
        ),
    };
    if cancelled || signals::interrupted() {
        return Err(Cancelled::nothing_changed().into());
    }
    Ok(result?)
}

pub fn say(message: impl Display) {
    let _ = writeln!(io::stdout().lock(), "{message}");
}

fn complain(message: impl Display) {
    let _ = writeln!(io::stderr().lock(), "{message}");
}

pub struct Spinner {
    bar: Option<cliclack::ProgressBar>,
    label: String,
}

impl Spinner {
    pub fn set_message(&self, message: impl Display) {
        if let Some(bar) = &self.bar {
            bar.set_message(message);
        }
    }

    pub fn stop(&self, message: impl Display) {
        match &self.bar {
            Some(bar) => bar.stop(message),
            None => say(message),
        }
    }

    pub fn check<T>(&self, result: Result<T>) -> Result<T> {
        result.map_err(|err| self.fail(err))
    }

    pub fn fail(&self, err: Error) -> Error {
        if let Some(bar) = &self.bar {
            match err.is::<Cancelled>() {
                true => bar.cancel(&self.label),
                false => bar.error(&self.label),
            }
        }
        err
    }
}
