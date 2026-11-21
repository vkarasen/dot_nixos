//! The two core domain types: [`Level`] and [`Record`].

use std::collections::BTreeMap;
use std::fmt;
use std::str::FromStr;

use serde::{Deserialize, Serialize};

use crate::error::ValidationError;
use crate::model::value::Component;

/// Severity of a log record, ordered from least to most severe.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Level {
    /// Fine-grained tracing.
    Trace,
    /// Developer-facing diagnostics.
    Debug,
    /// Normal operational messages.
    Info,
    /// Something recoverable went wrong.
    Warn,
    /// An operation failed.
    Error,
    /// The process cannot continue.
    Fatal,
}

impl Level {
    /// All levels, ordered by increasing severity.
    pub const ALL: [Self; Self::COUNT] = [
        Self::Trace,
        Self::Debug,
        Self::Info,
        Self::Warn,
        Self::Error,
        Self::Fatal,
    ];

    /// Number of variants, i.e. the column count of a count matrix.
    pub const COUNT: usize = 6;

    /// The canonical upper-case spelling used on the wire.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Trace => "TRACE",
            Self::Debug => "DEBUG",
            Self::Info => "INFO",
            Self::Warn => "WARN",
            Self::Error => "ERROR",
            Self::Fatal => "FATAL",
        }
    }

    /// Dense index in `0..Level::COUNT`, used as a matrix column.
    #[must_use]
    pub fn index(self) -> usize {
        usize::from(self.rank())
    }

    /// Zero-based severity rank; `Trace` is `0`, `Fatal` is `5`.
    #[must_use]
    pub const fn rank(self) -> u8 {
        match self {
            Self::Trace => 0,
            Self::Debug => 1,
            Self::Info => 2,
            Self::Warn => 3,
            Self::Error => 4,
            Self::Fatal => 5,
        }
    }
}

impl fmt::Display for Level {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl FromStr for Level {
    type Err = ValidationError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_ascii_uppercase().as_str() {
            "TRACE" => Ok(Self::Trace),
            "DEBUG" => Ok(Self::Debug),
            "INFO" => Ok(Self::Info),
            "WARN" => Ok(Self::Warn),
            "ERROR" => Ok(Self::Error),
            "FATAL" => Ok(Self::Fatal),
            _ => Err(ValidationError::UnknownLevel(s.to_owned())),
        }
    }
}

/// Attribute key reserved for the dependency edge.
pub const PARENT_ATTR: &str = "parent";

/// One parsed log record.
///
/// The struct is `serde`-derivable *and* [`bon::Builder`]-buildable: the
/// serde derives carry the wire representation while the builder makes
/// constructing fixtures in tests (and in the CLI) explicit at the call site.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, bon::Builder)]
pub struct Record {
    /// Milliseconds since the Unix epoch.
    pub ts_ms: u64,
    /// Severity.
    pub level: Level,
    /// Component that emitted the record.
    pub component: Component,
    /// Free-form key/value attributes, sorted by key.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub attrs: BTreeMap<String, String>,
}

impl Record {
    /// The component this record says it depends on, if any.
    ///
    /// Reads the reserved [`PARENT_ATTR`] attribute. The grammar already
    /// guarantees the value is a non-empty token, so it is a valid
    /// [`Component`] by construction.
    #[must_use]
    pub fn parent(&self) -> Option<&str> {
        self.attrs.get(PARENT_ATTR).map(String::as_str)
    }
}

impl fmt::Display for Record {
    /// Render the record back into the canonical single-line wire form.
    ///
    /// `Display` is not just for humans here: the round-trip property test
    /// asserts `parse_line(&record.to_string()) == record`.
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} {} {}", self.ts_ms, self.level, self.component)?;
        for (key, value) in &self.attrs {
            write!(f, " {key}={value}")?;
        }
        Ok(())
    }
}
